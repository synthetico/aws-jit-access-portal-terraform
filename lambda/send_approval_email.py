import json
import os
import boto3
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
sns = boto3.client('sns')

# Environment variables
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
APPROVAL_BASE_URL = os.environ['APPROVAL_BASE_URL']


def lambda_handler(event, context):
    """
    Send approval email to manager via SNS.

    Expected input from Step Functions:
    {
        "approval_id": "uuid",
        "requester_email": "user@example.com",
        "requester_name": "John Doe",
        "manager_email": "manager@example.com",
        "user_id": "SSO_USER_ID",
        "duration_hours": 4,
        "justification": "Emergency database access",
        "requested_at": "ISO 8601 timestamp"
    }
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")

        approval_id = event['approval_id']
        requester_email = event['requester_email']
        requester_name = event['requester_name']
        manager_email = event['manager_email']
        duration_hours = event['duration_hours']
        justification = event['justification']
        requested_at = event['requested_at']

        # Construct approval URLs
        approve_url = f"{APPROVAL_BASE_URL}?approval_id={approval_id}&decision=approve"
        deny_url = f"{APPROVAL_BASE_URL}?approval_id={approval_id}&decision=deny"

        # Email message
        subject = f"JIT Access Request - {requester_name}"

        message = f"""
JIT Access Approval Required

Requester: {requester_name} ({requester_email})
Requested Access: AdministratorAccess
Duration: {duration_hours} hours
Requested At: {requested_at}

Justification:
{justification}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

To approve or deny this request, click one of the links below:

✅ APPROVE: {approve_url}

❌ DENY: {deny_url}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This request will automatically expire in 24 hours if no action is taken.

Approval ID: {approval_id}
        """

        # Send email via SNS
        logger.info(f"Sending approval email to {manager_email}")

        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message,
            MessageAttributes={
                'email': {
                    'DataType': 'String',
                    'StringValue': manager_email
                }
            }
        )

        logger.info(f"SNS message sent: {response['MessageId']}")

        # Return event data for next step
        return {
            'approval_id': approval_id,
            'requester_email': requester_email,
            'requester_name': requester_name,
            'manager_email': manager_email,
            'user_id': event['user_id'],
            'duration_hours': duration_hours,
            'justification': justification,
            'requested_at': requested_at,
            'sns_message_id': response['MessageId']
        }

    except Exception as e:
        logger.error(f"Error sending approval email: {str(e)}", exc_info=True)
        raise
