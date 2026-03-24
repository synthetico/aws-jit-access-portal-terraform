import json
import os
import uuid
import boto3
from datetime import datetime, timedelta
from botocore.exceptions import ClientError
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
stepfunctions = boto3.client('stepfunctions')
cognito = boto3.client('cognito-idp')

# Environment variables
STEP_FUNCTIONS_ARN = os.environ['STEP_FUNCTIONS_ARN']
MAX_DURATION_HOURS = int(os.environ['MAX_DURATION_HOURS'])
USER_POOL_ID = os.environ['USER_POOL_ID']


def lambda_handler(event, context):
    """
    Lambda handler for initiating JIT access approval workflow.

    Expected input (from API Gateway with Cognito authorizer):
    {
        "user_id": "SSO_USER_ID",
        "duration_hours": 4,
        "justification": "Emergency database access"
    }
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")

        # Get authenticated user info from Cognito claims
        claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
        requester_email = claims.get('email')
        requester_name = claims.get('name', requester_email)
        manager_email = claims.get('custom:manager_email')

        if not requester_email:
            return error_response(401, "Unauthorized: Unable to identify user")

        if not manager_email:
            return error_response(400, "Manager email not set in user profile. Please update your profile.")

        # Parse request body
        body = parse_request_body(event)
        user_id = body.get('user_id')
        duration_hours = body.get('duration_hours', 4)
        justification = body.get('justification', 'JIT Access Request')

        # Validate inputs
        if not user_id:
            return error_response(400, "Missing required field: user_id")

        if duration_hours < 1 or duration_hours > MAX_DURATION_HOURS:
            return error_response(400, f"Duration must be between 1 and {MAX_DURATION_HOURS} hours")

        # Generate unique approval ID
        approval_id = str(uuid.uuid4())
        timestamp = datetime.utcnow()
        expiration_time = timestamp + timedelta(hours=24)  # Approval expires in 24 hours

        logger.info(f"Initiating approval workflow - ApprovalID: {approval_id}, Requester: {requester_email}")

        # Prepare Step Functions input
        sfn_input = {
            'approval_id': approval_id,
            'requester_email': requester_email,
            'requester_name': requester_name,
            'manager_email': manager_email,
            'user_id': user_id,
            'duration_hours': duration_hours,
            'justification': justification,
            'requested_at': timestamp.isoformat(),
            'expiration_time': int(expiration_time.timestamp())
        }

        # Start Step Functions execution
        logger.info(f"Starting Step Functions execution for approval {approval_id}")

        response = stepfunctions.start_execution(
            stateMachineArn=STEP_FUNCTIONS_ARN,
            name=f"approval-{approval_id}",
            input=json.dumps(sfn_input)
        )

        logger.info(f"Step Functions execution started: {response['executionArn']}")

        return success_response({
            'approval_id': approval_id,
            'requester_email': requester_email,
            'manager_email': manager_email,
            'duration_hours': duration_hours,
            'requested_at': timestamp.isoformat(),
            'status': 'PENDING_APPROVAL',
            'message': f'Access request submitted. Your manager ({manager_email}) will be notified for approval.',
            'execution_arn': response['executionArn']
        })

    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS API Error: {error_code} - {error_message}")

        if error_code == 'ExecutionAlreadyExists':
            return error_response(409, "An approval request with this ID already exists")
        else:
            return error_response(500, f"AWS API error: {error_message}")

    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        return error_response(500, f"Internal server error: {str(e)}")


def parse_request_body(event):
    """Parse and return the request body from API Gateway event."""
    if isinstance(event.get('body'), str):
        return json.loads(event['body'])
    return event.get('body', {})


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
