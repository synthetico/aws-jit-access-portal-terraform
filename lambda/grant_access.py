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
dynamodb = boto3.resource('dynamodb')
sso_admin = boto3.client('sso-admin')
scheduler = boto3.client('scheduler')

# Environment variables
DYNAMODB_TABLE_NAME = os.environ['DYNAMODB_TABLE_NAME']
SSO_INSTANCE_ARN = os.environ['SSO_INSTANCE_ARN']
TARGET_ACCOUNT_ID = os.environ['TARGET_ACCOUNT_ID']
PERMISSION_SET_ARN = os.environ['PERMISSION_SET_ARN']
MAX_DURATION_HOURS = int(os.environ['MAX_DURATION_HOURS'])
SCHEDULER_ROLE_ARN = os.environ['SCHEDULER_ROLE_ARN']
REVOKE_LAMBDA_ARN = os.environ['REVOKE_LAMBDA_ARN']
PROJECT_NAME = os.environ['PROJECT_NAME']
AWS_REGION = os.environ['AWS_REGION']

table = dynamodb.Table(DYNAMODB_TABLE_NAME)


def lambda_handler(event, context):
    """
    Lambda handler for granting JIT access via IAM Identity Center.

    Expected input:
    {
        "user_id": "user@example.com or USER_ID_FROM_SSO",
        "duration_hours": 4,
        "justification": "Emergency database access"
    }
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")

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

        # Generate unique request ID
        request_id = str(uuid.uuid4())
        timestamp = datetime.utcnow()
        expiration_time = timestamp + timedelta(hours=duration_hours)

        logger.info(f"Processing access request - RequestID: {request_id}, User: {user_id}, Duration: {duration_hours}h")

        # Create account assignment in IAM Identity Center
        assignment_response = create_account_assignment(user_id)

        # Store session metadata in DynamoDB
        store_session(
            request_id=request_id,
            user_id=user_id,
            duration_hours=duration_hours,
            justification=justification,
            timestamp=timestamp,
            expiration_time=expiration_time,
            assignment_id=assignment_response.get('AccountAssignmentCreationStatus', {}).get('RequestId')
        )

        # Create EventBridge Scheduler for automatic revocation
        scheduler_name = f"{PROJECT_NAME}-revoke-{request_id}"
        create_revocation_schedule(
            scheduler_name=scheduler_name,
            request_id=request_id,
            user_id=user_id,
            revoke_time=expiration_time
        )

        logger.info(f"Access granted successfully - RequestID: {request_id}")

        return success_response({
            'request_id': request_id,
            'user_id': user_id,
            'duration_hours': duration_hours,
            'granted_at': timestamp.isoformat(),
            'expires_at': expiration_time.isoformat(),
            'message': f'Access granted for {duration_hours} hours. Will be automatically revoked at {expiration_time.isoformat()}'
        })

    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS API Error: {error_code} - {error_message}")

        if error_code == 'ThrottlingException':
            return error_response(429, "Request throttled. Please try again later.")
        elif error_code == 'ConflictException':
            return error_response(409, "Access assignment already exists for this user.")
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


def create_account_assignment(user_id):
    """
    Create account assignment in IAM Identity Center with retry logic.

    Args:
        user_id: Principal ID (user ID from Identity Center)

    Returns:
        Response from create_account_assignment API call
    """
    max_retries = 3
    retry_delay = 1

    for attempt in range(max_retries):
        try:
            logger.info(f"Creating account assignment (attempt {attempt + 1}/{max_retries})")

            response = sso_admin.create_account_assignment(
                InstanceArn=SSO_INSTANCE_ARN,
                TargetId=TARGET_ACCOUNT_ID,
                TargetType='AWS_ACCOUNT',
                PermissionSetArn=PERMISSION_SET_ARN,
                PrincipalType='USER',
                PrincipalId=user_id
            )

            logger.info(f"Account assignment created: {response['AccountAssignmentCreationStatus']['RequestId']}")
            return response

        except ClientError as e:
            if e.response['Error']['Code'] == 'ThrottlingException' and attempt < max_retries - 1:
                logger.warning(f"Throttled, retrying in {retry_delay} seconds...")
                import time
                time.sleep(retry_delay)
                retry_delay *= 2
            else:
                raise


def store_session(request_id, user_id, duration_hours, justification, timestamp, expiration_time, assignment_id):
    """
    Store session metadata in DynamoDB.

    Args:
        request_id: Unique request identifier
        user_id: User principal ID
        duration_hours: Duration of access in hours
        justification: Reason for access
        timestamp: Request timestamp
        expiration_time: When access should be revoked
        assignment_id: SSO assignment request ID
    """
    item = {
        'RequestID': request_id,
        'UserID': user_id,
        'DurationHours': duration_hours,
        'Justification': justification,
        'GrantedAt': timestamp.isoformat(),
        'ExpiresAt': expiration_time.isoformat(),
        'ExpirationTime': int(expiration_time.timestamp()),  # TTL attribute (Unix timestamp)
        'Status': 'ACTIVE',
        'AssignmentID': assignment_id,
        'PermissionSetArn': PERMISSION_SET_ARN,
        'TargetAccountId': TARGET_ACCOUNT_ID
    }

    logger.info(f"Storing session in DynamoDB: {request_id}")
    table.put_item(Item=item)


def create_revocation_schedule(scheduler_name, request_id, user_id, revoke_time):
    """
    Create EventBridge Scheduler to automatically revoke access.

    Args:
        scheduler_name: Name of the schedule
        request_id: Unique request identifier
        user_id: User principal ID
        revoke_time: When to trigger revocation
    """
    # Format: at(yyyy-mm-ddThh:mm:ss)
    schedule_expression = f"at({revoke_time.strftime('%Y-%m-%dT%H:%M:%S')})"

    logger.info(f"Creating revocation schedule: {scheduler_name} at {revoke_time.isoformat()}")

    scheduler.create_schedule(
        Name=scheduler_name,
        ScheduleExpression=schedule_expression,
        Target={
            'Arn': REVOKE_LAMBDA_ARN,
            'RoleArn': SCHEDULER_ROLE_ARN,
            'Input': json.dumps({
                'request_id': request_id,
                'user_id': user_id
            }),
            'RetryPolicy': {
                'MaximumRetryAttempts': 3,
                'MaximumEventAgeInSeconds': 3600
            }
        },
        FlexibleTimeWindow={
            'Mode': 'OFF'
        },
        State='ENABLED',
        Description=f'Auto-revoke JIT access for request {request_id}'
    )

    logger.info(f"Revocation schedule created: {scheduler_name}")


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
