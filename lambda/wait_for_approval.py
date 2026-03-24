import json
import os
import boto3
from datetime import datetime, timedelta
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')

# Environment variables
APPROVAL_TABLE_NAME = os.environ['APPROVAL_TABLE_NAME']

table = dynamodb.Table(APPROVAL_TABLE_NAME)


def lambda_handler(event, context):
    """
    Store the Step Functions task token for callback later.

    Expected input from Step Functions:
    {
        "approval_id": "uuid",
        "task_token": "step_functions_task_token",
        "requester_email": "user@example.com",
        "manager_email": "manager@example.com"
    }
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")

        approval_id = event['approval_id']
        task_token = event['task_token']

        # Store task token in DynamoDB for later callback
        logger.info(f"Storing task token for approval: {approval_id}")

        table.update_item(
            Key={'ApprovalID': approval_id},
            UpdateExpression='SET TaskToken = :token, WaitingStartedAt = :started_at',
            ExpressionAttributeValues={
                ':token': task_token,
                ':started_at': datetime.utcnow().isoformat()
            }
        )

        logger.info(f"Task token stored for approval: {approval_id}")

        # The Lambda exits here, but Step Functions waits for callback
        # The callback will be triggered by the process_approval Lambda

    except Exception as e:
        logger.error(f"Error storing task token: {str(e)}", exc_info=True)
        raise
