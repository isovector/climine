#!/usr/bin/python
import smtplib
import os
import mimetypes
from email.MIMEMultipart import MIMEMultipart
from email.MIMEBase import MIMEBase
from email.MIMEText import MIMEText
from email.MIMEAudio import MIMEAudio
from email.MIMEImage import MIMEImage
from email.Encoders import encode_base64
import difflib
import subprocess

emailAddress = '' #Enter your email address here
emailPassword = '' #Enter your password here
recipient = '' #Enter the recipient here
smtpaddress = ''#Enter SMTP address of mail server here

###########################################################
# CLImail - a script to send email updates for jobmine    #
#    written by Arvin Aminpour (aaminpou@uwaterloo.ca)    #
#                                                         #
# Last revised 2012-05-19                                 #
#                                                         #
# This software is licensed under the GPLv2               #
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html   #
###########################################################


def check_for_updates():
    firsttime = False
    file = open_last_update("r")
    if file:
        lastupdate = file.read()
        file.close()
    else:
        lastupdate = ""
        firsttime = True
    pipe = subprocess.Popen(["./climine.pl", ""], stdout=subprocess.PIPE)
    result = pipe.stdout.read()
    if firsttime:
        sendMail("New Jobmine Update", result)
    elif result != lastupdate:
        sendMail("New Jobmine Update", result)
        file = open_last_update("w")
        file.write(result) #Update with new jobs
        file.close


def open_last_update(in_mode):
    try:
        file = open('/tmp/lastupdate.txt', mode=in_mode)
    except IOError as e:
        file = None
    return file


def sendMail(subject, text, *attachmentFilePaths):
    global emailAddress, emailPassword, recipient, smtpaddress
    msg = MIMEMultipart()
    msg['From'] = emailAddress
    msg['To'] = recipient
    msg['Subject'] = subject
    msg.attach(MIMEText(text))
    mailServer = smtplib.SMTP(smtpaddress, 587)
    mailServer.ehlo()
    mailServer.starttls()
    mailServer.ehlo()
    mailServer.login(emailAddress, emailPassword)
    mailServer.sendmail(emailAddress, recipient, msg.as_string())
    mailServer.close()

if __name__ == '__main__':
    check_for_updates()
