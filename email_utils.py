import base64
import os
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage

from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from httplib2 import Http
from oauth2client import file, client, tools


def create_message(email_address, subject, pages_folder, first, count):
    """ Create a message that has the correct number of attachments """

    # Create the root message and fill in the from, to, and subject headers
    msg_root = MIMEMultipart("related")
    msg_root["Subject"] = subject
    msg_root["From"] = email_address
    msg_root["To"] = email_address
    msg_root.preamble = "This is a multi-part message in MIME format."

    # Encapsulate the plain and HTML versions of the message body in an
    # 'alternative' part, so message agents can decide which they want to display.
    msg_alternative = MIMEMultipart("alternative")
    msg_root.attach(msg_alternative)

    msg_text = MIMEText("There is no alternative plain text message!")
    msg_alternative.attach(msg_text)

    # We reference the image in the IMG SRC attribute by the ID we give it below
    msg_text = ""
    for i in range(first, first + count):
        msg_text += f'<img src="cid:image{i}">'
    msg_alternative.attach(MIMEText(msg_text, "html"))

    # This example assumes the image is in the current directory
    os.chdir(pages_folder)
    for i in range(first, first + count):
        input_file = f"page-{i:03}.png"
        print(f"Adding page: {input_file}...")
        with open(input_file, "rb") as input_handle:
            msg_image = MIMEImage(input_handle.read())

        # Define the image's ID as referenced above
        msg_image.add_header("Content-ID", f"<image{i}>")
        msg_root.attach(msg_image)
    os.chdir(os.path.dirname(pages_folder))

    payload = base64.urlsafe_b64encode(msg_root.as_string().encode("ascii"))
    return {"raw": payload.decode("ascii")}


def send_message(message):
    """Send an email message.

    Args:
    service: Authorized Gmail API service instance.
    message: Message to be sent.

    Returns:
    Sent Message.
    """
    token_file = os.path.join(os.path.dirname(__file__), "token.json")
    creds_file = os.path.join(os.path.dirname(__file__), "credentials.json")

    store = file.Storage(token_file)
    creds = store.get()
    if not creds or creds.invalid:
        # If modifying these scopes, delete the file token.json.
        flow = client.flow_from_clientsecrets(creds_file, "https://www.googleapis.com/auth/gmail.send")
        creds = tools.run_flow(flow, store)
    service = build("gmail", "v1", http=creds.authorize(Http()))

    try:
        message = service.users().messages().send(userId="me", body=message).execute()
        print("Message Id: %s" % message["id"])
        return message
    except HttpError as error:
        print("An error occurred: %s" % error)
