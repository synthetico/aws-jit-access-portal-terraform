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
sso_admin = boto3.client('sso-admin')
scheduler = boto3.client('scheduler')

# Environment variables
DYNAMODB_TABLE_NAME = os.environ['DYNAMODB_TABLE_NAME']
SSO_INSTANCE_ARN = os.environ['SSO_INSTANCE_ARN']
TARGET_ACCOUNT_ID = os.environ['TARGET_ACCOUNT_ID']
PERMISSION_SET_ARN = os.environ['PERMISSION_SET_ARN']

table = dynamodb.Table(DYNAMODB_TABLE_NAME)


def lambda_handler(event, context):
    """
    Lambda handler for revoking JIT access via IAM Identity Center.

    Expected input (from EventBridge Scheduler):
    {
        "request_id": "uuid-string",
        "user_id": "user@example.com or USER_ID_FROM_SSO"
    }
    """
    try:
        logger.info(f"Received revocation event: {json.dumps(event)}")

        # Parse event
        request_id = event.get('request_id')
        user_id = event.get('user_id')

        if not request_id or not user_id:
            raise ValueError("Missing required fields: request_id and user_id")

        logger.info(f"Processing revocation - RequestID: {request_id}, User: {user_id}")

        # Retrieve session from DynamoDB
        session = get_session(request_id)

        if not session:
            logger.warning(f"Session not found in DynamoDB: {request_id}")
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'Session not found'})
            }

        # Verify user_id matches
        if session.get('UserID') != user_id:
            logger.error(f"User ID mismatch. Expected: {session.get('UserID')}, Got: {user_id}")
            raise ValueError("User ID mismatch")

        # Delete account assignment in IAM Identity Center
        delete_account_assignment(user_id)

        # Update session status in DynamoDB
        update_session_status(request_id, 'REVOKED')

        # Delete the EventBridge Scheduler (cleanup)
        delete_schedule(request_id)

        logger.info(f"Access revoked successfully - RequestID: {request_id}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'request_id': request_id,
                'user_id': user_id,
                'revoked_at': datetime.utcnow().isoformat(),
                'message': 'Access revoked successfully'
            })
        }

    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS API Error: {error_code} - {error_message}")

        # Handle specific error cases
        if error_code == 'ResourceNotFoundException':
            logger.warning("Assignment not found - may have been manually removed")
            update_session_status(request_id, 'REVOKED')
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'Assignment already removed'})
            }
        elif error_code == 'ThrottlingException':
            logger.error("Throttled by AWS API - will retry via scheduler retry policy")
            raise  # Re-raise to trigger EventBridge retry
        else:
            raise

    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        raise  # Re-raise to trigger EventBridge retry


def get_session(request_id):
    """
    Retrieve session from DynamoDB.

    Args:
        request_id: Unique request identifier

    Returns:
        Session item or None if not found
    """
    try:
        logger.info(f"Retrieving session from DynamoDB: {request_id}")
        response = table.get_item(Key={'RequestID': request_id})
        return response.get('Item')
    except ClientError as e:
        logger.error(f"Error retrieving session: {str(e)}")
        raise


def delete_account_assignment(user_id):
    """
    Delete account assignment in IAM Identity Center with retry logic.

    Args:
        user_id: Principal ID (user ID from Identity Center)

    Returns:
        Response from delete_account_assignment API call
    """
    max_retries = 3
    retry_delay = 1

    for attempt in range(max_retries):
        try:
            logger.info(f"Deleting account assignment (attempt {attempt + 1}/{max_retries})")

            response = sso_admin.delete_account_assignment(
                InstanceArn=SSO_INSTANCE_ARN,
                TargetId=TARGET_ACCOUNT_ID,
                TargetType='AWS_ACCOUNT',
                PermissionSetArn=PERMISSION_SET_ARN,
                PrincipalType='USER',
                PrincipalId=user_id
            )

            logger.info(f"Account assignment deleted: {response['AccountAssignmentDeletionStatus']['RequestId']}")
            return response

        except ClientError as e:
            if e.response['Error']['Code'] == 'ThrottlingException' and attempt < max_retries - 1:
                logger.warning(f"Throttled, retrying in {retry_delay} seconds...")
                import time
                time.sleep(retry_delay)
                retry_delay *= 2
            else:
                raise


def update_session_status(request_id, status):
    """
    Update session status in DynamoDB.

    Args:
        request_id: Unique request identifier
        status: New status (e.g., 'REVOKED', 'FAILED')
    """
    try:
        logger.info(f"Updating session status to {status}: {request_id}")

        table.update_item(
            Key={'RequestID': request_id},
            UpdateExpression='SET #status = :status, RevokedAt = :revoked_at',
            ExpressionAttributeNames={
                '#status': 'Status'
            },
            ExpressionAttributeValues={
                ':status': status,
                ':revoked_at': datetime.utcnow().isoformat()
            }
        )

        logger.info(f"Session status updated: {request_id}")

    except ClientError as e:
        logger.error(f"Error updating session status: {str(e)}")
        # Don't raise - this is a non-critical operation


def delete_schedule(request_id):
    """
    Delete EventBridge Scheduler after successful revocation.

    Args:
        request_id: Unique request identifier
    """
    try:
        # Extract project name from environment if available
        project_name = os.environ.get('PROJECT_NAME', 'tdemy-jit-portal')
        schedule_name = f"{project_name}-revoke-{request_id}"

        logger.info(f"Deleting EventBridge schedule: {schedule_name}")

        scheduler.delete_schedule(Name=schedule_name)

        logger.info(f"Schedule deleted: {schedule_name}")

    except ClientError as e:
        error_code = e.response['Error']['Code']

        if error_code == 'ResourceNotFoundException':
            logger.warning(f"Schedule not found (may have been auto-deleted): {schedule_name}")
        else:
            logger.error(f"Error deleting schedule: {str(e)}")
            # Don't raise - this is cleanup, not critical

    except Exception as e:
        logger.error(f"Unexpected error deleting schedule: {str(e)}")
        # Don't raise - this is cleanup, not critical
