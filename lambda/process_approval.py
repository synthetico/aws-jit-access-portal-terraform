import json
import os
import boto3
from datetime import datetime
from botocore.exceptions import ClientError
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
stepfunctions = boto3.client('stepfunctions')
cognito = boto3.client('cognito-idp')

# Environment variables
APPROVAL_TABLE_NAME = os.environ['APPROVAL_TABLE_NAME']
USER_POOL_ID = os.environ['USER_POOL_ID']

table = dynamodb.Table(APPROVAL_TABLE_NAME)


def lambda_handler(event, context):
    """
    Process approval/denial decision and send callback to Step Functions.

    Expected input (from API Gateway with Cognito authorizer):
    {
        "approval_id": "uuid",
        "decision": "approve" or "deny",
        "denial_reason": "optional reason for denial",
        "cognito_username": "from authorizer context"
    }
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")

        # Parse request
        body = parse_request_body(event)
        approval_id = body.get('approval_id')
        decision = body.get('decision', '').lower()
        denial_reason = body.get('denial_reason', 'No reason provided')

        # Get approver info from Cognito claims
        claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
        approver_email = claims.get('email', 'Unknown')
        approver_name = claims.get('name', approver_email)

        if not approval_id or decision not in ['approve', 'deny']:
            return error_response(400, "Invalid request. Provide approval_id and decision (approve/deny)")

        logger.info(f"Processing {decision} for approval {approval_id} by {approver_email}")

        # Retrieve approval request from DynamoDB
        approval_request = get_approval_request(approval_id)

        if not approval_request:
            return error_response(404, "Approval request not found")

        # Check if already processed
        status = approval_request.get('Status')
        if status != 'PENDING':
            return error_response(409, f"Approval already processed with status: {status}")

        # Verify approver is the manager
        manager_email = approval_request.get('ManagerEmail')
        if approver_email.lower() != manager_email.lower():
            logger.warning(f"Unauthorized approval attempt by {approver_email} for request assigned to {manager_email}")
            return error_response(403, "You are not authorized to approve this request")

        # Get task token
        task_token = approval_request.get('TaskToken')
        if not task_token:
            return error_response(500, "Task token not found for this approval")

        # Prepare callback payload
        timestamp = datetime.utcnow().isoformat()

        if decision == 'approve':
            callback_output = {
                'approval_id': approval_id,
                'decision': 'APPROVED',
                'approved_by': approver_email,
                'approved_at': timestamp,
                'user_id': approval_request.get('UserID'),
                'duration_hours': approval_request.get('DurationHours'),
                'justification': approval_request.get('Justification')
            }
            logger.info(f"Sending success callback to Step Functions for approval {approval_id}")
            stepfunctions.send_task_success(
                taskToken=task_token,
                output=json.dumps(callback_output)
            )
            message = "Access request approved successfully"

        else:  # deny
            callback_output = {
                'approval_id': approval_id,
                'decision': 'DENIED',
                'denied_by': approver_email,
                'denied_at': timestamp,
                'denial_reason': denial_reason
            }
            logger.info(f"Sending failure callback to Step Functions for approval {approval_id}")
            stepfunctions.send_task_failure(
                taskToken=task_token,
                error='ApprovalDenied',
                cause=json.dumps(callback_output)
            )
            message = "Access request denied"

        return success_response({
            'approval_id': approval_id,
            'decision': decision,
            'approver': approver_email,
            'timestamp': timestamp,
            'message': message
        })

    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS API Error: {error_code} - {error_message}")
        return error_response(500, f"AWS API error: {error_message}")

    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        return error_response(500, f"Internal server error: {str(e)}")


def parse_request_body(event):
    """Parse request body from API Gateway event."""
    body = event.get('body', '{}')
    if isinstance(body, str):
        return json.loads(body)
    return body


def get_approval_request(approval_id):
    """Retrieve approval request from DynamoDB."""
    try:
        response = table.get_item(Key={'ApprovalID': approval_id})
        return response.get('Item')
    except ClientError as e:
        logger.error(f"Error retrieving approval request: {str(e)}")
        return None


def success_response(data):
    """Return successful API response."""
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(data)
    }


def error_response(status_code, message):
    """Return error API response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'error': message
        })
    }
