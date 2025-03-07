#!/usr/bin/env python3
import http.client
import base64
import datetime, timezone
import json
import logging
import time
import os
import urllib3
import requests
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import email.mime.application
import socket
import concurrent.futures
from kubernetes import client, config
import pytz
import ssl
import pymongo
import sqlalchemy
import psycopg2
from sqlalchemy import text
from google.cloud.sql.connector import Connector, IPTypes
import argparse

# Defining global variables
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
sender = 'donotreply_SREAutomation@company.com'
to_list = ['chetan.kolur@company.com']
app_home = os.path.basename(__file__.rsplit('.', 1)[0])
scripts_dir = os.path.dirname(os.path.realpath(__file__)).replace('install/', 'run')
app_home_dir = os.path.dirname(scripts_dir)
config_dir = os.path.join(scripts_dir, 'cfg')
data_dir = os.path.join(app_home_dir, 'data')
output_dir = os.path.join(app_home_dir, 'output')
# Global vars getpod kub
db_instance_id = ""
schemaname = ""
sa_username = ""
greenColor = '86FF33'
redColor = 'FF4935'
pod_status_data = ''
pod_log_data = ''
endpoint_data = ''
region = ''
env_name = ''
dbstatus_data = ''
dbcount_data = ''

# Configure logging
logging.basicConfig(level=logging.INFO, 
                    format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# code base from getpods & db_availability
def generateHtmlData(maildata, flag):
    if flag == 'pods':
        tabledata = '''
        <section style="border: thin solid black" align="center"><br>
            Report Module: <strong>Pod Status</strong><br>
        <table border="1px solid black" align="center">
        <tbody>
            <tr>
                <td>&nbsp;Pod Name &nbsp;</td>
                <td>&nbsp;String &nbsp;</td>
                <td>&nbsp;Status &nbsp;</td>
            </tr>''' + maildata + '''
        </tbody>
        </table>
        </section>
        '''
    elif flag == 'endpoints':
        tabledata = '''
        <section style="border: thin solid black" align="center"><br>
            Report Module: <strong>Endpoints status</strong><br>
        <table border="1px solid black" align="center">
        <tbody>
            <tr>
                <td>&nbsp;Endpoint &nbsp;</td>
                <td>&nbsp;Status Code &nbsp;</td>
                <td>&nbsp;Elapsed Time (ms) &nbsp;</td>
            </tr>''' + maildata + '''
        </tbody>
        </table>
        </section>
        '''
    elif flag == 'status':
        tabledata = '''
        <section style="border: thin solid black" align="center"><br>
            Report Module: <strong>Database status</strong><br>
        <table border="1px solid black" align="center">
        <tbody>
            <tr>
                <td>&nbsp;Status &nbsp;</td>
            </tr>''' + maildata + '''
        </tbody>
        </table>
        </section>
        '''
    elif flag == 'dcount':
        tabledata = '''
        <section style="border: thin solid black" align="center"><br>
            Report Module: <strong>Database runs modified count</strong><br>
        <table border="1px solid black" align="center">
        <tbody>
            <tr>
                <td>&nbsp;Count &nbsp;</td>
            </tr>''' + maildata + '''
        </tbody>
        </table>
        </section>
        '''

    return tabledata

def sendMail(sender, to_list, cc_list, subj):
    msg = MIMEMultipart('alternative')
    msg['Subject'] = subj
    msg['From'] = sender
    msg['To'] = ", ".join(to_list)
    msg['Cc'] = ", ".join(cc_list)
    msg['Content-Type'] = 'text/html'
    body = MIMEMultipart('alternative')
    body.attach(MIMEText(text.encode('utf-8'), 'html', _charset='utf-8'))
    msg.attach(body)

    try:
        s = smtplib.SMTP('smtp.merc.chicago.cms.com', 25)
        s.sendmail(sender, (to_list+cc_list), msg.as_string())
        s.quit()
    except Exception as e:
        logger.info(f"Error while sending mail: {e}")

def check_logs_for_string(namespace, pod_name, container_name, search_string):
    """
    Checks if a specific string exists in the logs of a pod.
    
    Args:
        namespace: The namespace of the pod.
        pod_name: The name of the pod.
        container_name: The name of the container within the pod.
        search_string: The string to search for in the logs.
        
    Returns:
        True if the string is found in the logs, False otherwise.
    """
    # Load kubernetes configuration
    try:
        config.load_kube_config()
    except config.config_exception.ConfigException:
        logger.info("Couldn't load kube config, trying in cluster")
        config.load_incluster_config()

    print("Config loaded successfully")
    api_instance = client.CoreV1Api()

    # Get all pod logs
    logs = api_instance.read_namespaced_pod_log(
        namespace=namespace,
        name=pod_name,
        container=container_name
    )

    # Check if the string is present in the logs
    if search_string in logs:
        return True, logs
    else:
        return False, None

def get_pod_logs(namespace_name, container_name, search_string, comp_id):
    global pod_log_data
    
    # Load kubernetes configuration
    try:
        config.load_kube_config()
    except config.config_exception.ConfigException:
        logger.info("Couldn't load kube config, trying in cluster")
        config.load_incluster_config()
        
    api_instance = client.CoreV1Api()
    
    pod_list = api_instance.list_namespaced_pod(namespace=namespace_name)
    
    logger.info("--> pod")
    for pod in pod_list.items:
        if comp_id in pod.metadata.name:
            string_found_logs = check_logs_for_string(namespace_name, pod.metadata.name, container_name, search_string)
            
            if string_found_logs:
                logger.info(f"String '{search_string}' found in the logs of pod '{pod.metadata.name}'")
                pod_log_data = pod_log_data + f"<tr><td style='background-color:#{greenColor};font-weight:bold'>&nbsp; {pod.metadata.name} &nbsp;</td><td>&nbsp; {search_string} &nbsp;</td><td style='background-color:#{greenColor};font-weight:bold'>&nbsp; Reachable &nbsp;</td></tr>"
            else:
                logger.info(f"String '{search_string}' not found in the logs of pod '{pod.metadata.name}'")
                pod_log_data = pod_log_data + f"<tr><td style='background-color:#{redColor};font-weight:bold'>&nbsp; {pod.metadata.name} &nbsp;</td><td>&nbsp; {search_string} &nbsp;</td><td style='background-color:#{redColor};font-weight:bold'>&nbsp; Unreachable &nbsp;</td></tr>"
    
    return pod_log_data

def get_pod_status(namespace_name):
    global pod_status_data
    
    # Load kubernetes configuration
    try:
        config.load_kube_config()
    except config.config_exception.ConfigException:
        logger.info("Couldn't load kube config, trying in cluster")
        config.load_incluster_config()
        
    api_instance = client.CoreV1Api()
    
    pod_list = api_instance.list_namespaced_pod(namespace=namespace_name)
    
    logger.info("--> pod")
    for pod in pod_list.items:
        if pod.status.phase == 'Running':
            pod_status_data = pod_status_data + f"<tr><td style='background-color:#{greenColor};font-weight:bold'>&nbsp; {pod.metadata.name} &nbsp;</td><td>&nbsp; {pod.status.phase} &nbsp;</td><td style='background-color:#{greenColor};font-weight:bold'>&nbsp; Reachable &nbsp;</td></tr>"
        else:
            pod_status_data = pod_status_data + f"<tr><td style='background-color:#{redColor};font-weight:bold'>&nbsp; {pod.metadata.name} &nbsp;</td><td>&nbsp; {pod.status.phase} &nbsp;</td><td style='background-color:#{redColor};font-weight:bold'>&nbsp; Unreachable &nbsp;</td></tr>"
    
    return pod_status_data

def postgres_connection(cloud_project):
    global dbstatus_data
    
    try:
        connector = Connector()
        connection = connector.connect(
            instance_name=f"{cloud_project}:us-central1:postgres",
            driver="postgres",
            user=sa_username,
            password=password,
            db="postgres"
        )
        
        if connection:
            cursor = connection.cursor()
            record = cursor.execute("SELECT VERSION();").fetchone()
            if record:
                dbstatus_data = dbstatus_data + f"<tr><td style='background-color:#{greenColor};font-weight:bold'>&nbsp; {cloud_project} &nbsp;</td><td style='background-color:#{greenColor};font-weight:bold'>&nbsp; Reachable &nbsp;</td></tr>"
            else:
                dbstatus_data = dbstatus_data + f"<tr><td style='background-color:#{redColor};font-weight:bold'>&nbsp; {cloud_project} &nbsp;</td><td style='background-color:#{redColor};font-weight:bold'>&nbsp; Unreachable &nbsp;</td></tr>"
            return dbstatus_data
        else:
            dbstatus_data = dbstatus_data + f"<tr><td style='background-color:#{redColor};font-weight:bold'>&nbsp; {cloud_project} &nbsp;</td><td style='background-color:#{redColor};font-weight:bold'>&nbsp; Unreachable &nbsp;</td></tr>"
            return dbstatus_data
    except Exception as e:
        logger.info(f"Connect to PostgreSQL error: {e}")
        dbstatus_data = dbstatus_data + f"<tr><td style='background-color:#{redColor};font-weight:bold'>&nbsp; {cloud_project} &nbsp;</td><td style='background-color:#{redColor};font-weight:bold'>&nbsp; Unreachable &nbsp;</td></tr>"
        return dbstatus_data

def basic_auth(username, password):
    token = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
    return f"Basic {token}"

# get the headers file from the cli
def get_headers(headers_file, username, password):
    logger.info(f"Loading headers from {headers_file}")
    with open(headers_file) as f:
        headers = json.load(f)
        logger.info(headers)
    
    requires_auth = headers.get('requires_auth')
    
    # Format the datetime as a string
    now = datetime.datetime.now()
    if requires_auth.lower() == 'true':
        headers['Authorization'] = basic_auth(username, password)
        timestamp = now.strftime("%Y-%m-%d %H:%M:%S.%f")
        timest = timestamp[:-3]
        headers['Timestamp'] = timest
    
    return headers

# get endpoints file from the cli
def get_endpoints(endpoints_file):
    with open(endpoints_file) as f:
        endpoints = json.load(f)
        return endpoints

# hit the endpoint called by main method
def call_endpoint_worker(endpoint, value, headers, timeout):  # Timeout in seconds (5 min = 300 sec)
    start_time = time.time()
    logger.info(f"Calling endpoint: {endpoint}")
    logger.debug(f"Endpoint details: {value}")
    logger.debug(value['method'])
    logger.debug(headers['requires_auth'])
    
    try:
        #print("Entered try")
        # Use a with statement for better connection management and timeout handling
        if value['method'] == 'POST':
            logger.debug("Inside post")
            conn = http.client.HTTPSConnection(value['host'], timeout=timeout)
            conn.request(value['method'], value['path'], json.dumps(value['payload']), headers)
            #print(conn)
            #print(conn.getresponse())
        
        elif value['method'] == 'GET' and headers['requires_auth'].lower() == 'false':
            logger.info("Inside get")
            try:
                # print("Inside get try block")
                # pass_headers=headers
                # print(type(pass_headers))
                # print(headers)
                #pass_headers.pop('requires_auth')
                # del pass_headers['requires_auth']
                # print(pass_headers)
                # print(headers)
                
                # except Exception as e:
                # print(f"Inside get except block: {e}")
                # pass
                
                # print(pass_headers)
                # print(headers)
                # print(endpoint)
                
                logger.debug(headers)
                
                conn = http.client.HTTPSConnection(value['host'], timeout=timeout)
                conn.request(value['method'], value['path'], json.dumps(value['payload']), headers)
            except Exception as e:
                print(f"Inside get except block: {e}")
                pass
        
        elif value['method'] == 'GET' and headers['requires_auth'].lower() == 'true':
            conn = http.client.HTTPSConnection(value['host'], timeout=timeout)
            conn.request(value['method'], value['path'], json.dumps(value['payload']), headers)
            
        res = conn.getresponse()
        logger.info(f"Status code for {endpoint}: {res.status}")
        data = res.read()
        
        end_time = time.time()
        elapsed_time = round((end_time - start_time) * 1000)
        
        # logger.info(f"Status code for {endpoint}: {res.status}")
        # logger.info(f"Elapsed time for {endpoint}: {elapsed_time} ms")
        
        return {
            "endpoint": endpoint,
            "status_code": res.status,
            "elapsed_time": elapsed_time
        }
    
    except (http.client.HTTPException, socket.timeout, socket.error) as e:
        end_time = time.time()
        elapsed_time = round((end_time - start_time) * 1000)
        if isinstance(e, socket.timeout):  # Explicit timeout check
            logger.warning(f"Timeout occurred for endpoint {endpoint} after {timeout} seconds.")
            status_code = -2  # Timeout error status code
        else:
            logger.exception(f"Error calling endpoint {endpoint}: {e}")
            status_code = -1  # Generic error status code
        
        return {
            "endpoint": endpoint,
            "status_code": status_code,
            "elapsed_time": elapsed_time if status_code == -1 else timeout*1000
        }

def init_pool_connection(connector):
    # Function used to generate database connection
    conn = connector.connect(
        instance_name=db_instance_id,
        driver="postgres",
        user=sa_username,
        password="",  # Insert appropriate password handling
        db=schemaname
    )
    return conn

def runQuery(connection, cursor, query, type):
    if type == "status":
        record = cursor.execute(query).fetchone()
        if record:
            dbstatus_data = f"<tr><td style='background-color:#{greenColor};font-weight:bold'>&nbsp; Reachable &nbsp;</td></tr>"
        else:
            dbstatus_data = f"<tr><td style='background-color:#{redColor};font-weight:bold'>&nbsp; Unreachable &nbsp;</td></tr>"
        return dbstatus_data
    elif type == "dcount":
        record = cursor.execute(query).fetchone()
        if record:
            dbcount_data = f"<tr><td style='background-color:#{greenColor};font-weight:bold'>&nbsp; {str(record[0])} &nbsp;</td></tr>"
        else:
            dbcount_data = f"<tr><td style='background-color:#{redColor};font-weight:bold'>&nbsp; 0 &nbsp;</td></tr>"
        return dbcount_data
    else:
        return "Unknown query type"

# main method to collect all details and call the call_endpoint
def main():
    # Global variables declaration
    global pod_status_data, pod_log_data, endpoint_data, dbcount_data, db_instance_id, schemaname, sa_username, sender
    
    # Argument parsing
    parser = argparse.ArgumentParser(description="Kubernetes Pod Information Script")
    parser.add_argument("--pod_status", help="accepts true/false value", default="false")
    parser.add_argument("--pod_logs", help="accepts true/false value, default='false'", default="false")
    parser.add_argument("--dbstatus", help="DB Status accepts true/false value", default="false")
    parser.add_argument("--endpoints_file", help="Path to the endpoints configuration file (optional), default: prod_endpoints.conf")
    parser.add_argument("--header_file", help="Required to pass the headers to the endpoint", default="cuapi_header.conf")
    parser.add_argument("--username", help="Username for authentication")
    parser.add_argument("--password", help="Password for authentication")
    parser.add_argument("--timeout", help="Required to pass the headers to the endpoint", default=300)
    parser.add_argument("--level", help="Set the logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)", default="INFO")
    parser.add_argument("--namespace", help="Kubernetes pod Information Script")
    parser.add_argument("--email", help="Report will be sent to given email ids, pass comma separated values")
    parser.add_argument("--search_string", help="search string")
    parser.add_argument("--schemaname", help="DB Schemaname")
    parser.add_argument("--sa_username", help="Service account name")
    parser.add_argument("--comp_id", help="Component ID to fetch logs")
    parser.add_argument("--pod_name", help="The name of the pod")
    parser.add_argument("--container_name", help="The name of the container within the pod")
    parser.add_argument("--url", help="Health check url without endpoint")
    parser.add_argument("--endpoint", help="endpoint of url")
    parser.add_argument("--columnname", help="POD runs modified count: True/False value", default="false")
    parser.add_argument("--tablename", help="POD runs modified timestamp column name")
    parser.add_argument("--days", help="Current day minus how many")
    parser.add_argument("--region", help="Cluster region name(us/eu/apj)")
    # ADDED: New parameter for interval between runs
    parser.add_argument("--interval", help="Interval between runs in minutes", type=int, default=2)
    
    args = parser.parse_args()
    
    # Set up logging configuration - do this once outside the loop
    checkout_start_time = time.time()
    logger.info(f"Checkout started: {time.ctime(checkout_start_time)}")
    numeric_level = getattr(logging, args.level.upper(), None)
    if not isinstance(numeric_level, int):
        logger.warning(f"Invalid log level: {args.level}")
        numeric_level = getattr(logging, "INFO", None)
    logger.setLevel(numeric_level)
    
    logger.info(f"Setting level set to: {args.level.upper()}")
    logger.info(f"Logging level set to: {numeric_level}")
    
    # Set up email recipients
    if args.email:
        to_list = args.email.split(',')
    cc_list = []
    
    # Set up DB variables
    schemaname = args.schemaname
    db_instance_id = args.db_instance_id
    sa_username = args.sa_username
    
    # ADDED: Log the start of pod-based execution with interval information
    logger.info(f"Starting probe in pod mode with {args.interval} minute intervals")
    
    # ADDED: Main loop for continuous execution - this is the key change to convert to pod style
    while True:
        try:
            # Reset data variables for this iteration
            pod_status_data = ''
            pod_log_data = ''
            endpoint_data = ''
            dbstatus_data = ''
            dbcount_data = ''
            maildata = ''
            
            # Log start of this cycle
            cycle_start_time = time.time()
            logger.info(f"Starting new probe cycle at {time.ctime(cycle_start_time)}")
            
            # Execute tasks based on arguments - Kubernetes pod status check
            if args.pod_status.lower() == 'true':
                get_pod_status(args.namespace)
                maildata = maildata + generateHtmlData(pod_status_data, 'pods')
            
            # Get pod logs check
            if args.pod_logs.lower() == 'true':
                if len(args.comp_id.split(",")) > 1:
                    for i in range(0, len(args.comp_id.split(","))):
                        get_pod_logs(args.namespace, args.container_name.split(",")[i], args.search_string, args.comp_id.split(",")[i])
                else:
                    get_pod_logs(args.namespace, args.container_name, args.search_string, args.comp_id)
                maildata = maildata + generateHtmlData(pod_log_data, 'logs')
                
            # Database status check
            if args.dbstatus.lower() == 'true':
                try:
                    connector = Connector()
                    connection = init_pool_connection(connector)
                    cursor = connection.cursor()
                    dbstatus_data = runQuery(connection, cursor, "SELECT VERSION();", "status")
                    maildata = maildata + generateHtmlData(dbstatus_data, 'status')
                except Exception as e:
                    logger.warning(f"{e}")
                    maildata = maildata + generateHtmlData("<tr><td style='background-color:red;font-weight:bold'>&nbsp; Database Connection Error &nbsp;</td></tr>", 'status')
                finally:
                    if 'connector' in locals():
                        connector.close()
                
            # Database count check
            if args.columnname.lower() == 'true':
                try:
                    connector = Connector()
                    connection = init_pool_connection(connector)
                    cursor = connection.cursor()
                    my_query = f"SELECT COUNT(*) FROM {args.schemaname}.{args.tablename} WHERE {args.tablename}.{'date' if 'date' in args.columnname else args.columnname} > CURRENT_DATE - {args.days} "
                    dbcount_data = runQuery(connection, cursor, my_query, "dcount")
                    maildata = maildata + generateHtmlData(dbcount_data, 'dcount')
                except Exception as e:
                    logger.warning(f"{e}")
                    maildata = maildata + generateHtmlData("<tr><td style='background-color:red;font-weight:bold'>&nbsp; Database Count Error &nbsp;</td></tr>", 'dcount')
                finally:
                    if 'connector' in locals():
                        connector.close()
                
            # Check if endpoints should be checked
            if args.endpoints_file:
                # Load configuration files
                endpoints_file = args.endpoints_file or "cuapi_prod_endpoints_use5.conf"  # Default
                logger.debug(f"Loading endpoints from {endpoints_file}")
                endpoints = get_endpoints(os.path.join(config_dir, endpoints_file))  # Use config_dir for file location
                headers_file = args.header_file or "cuapi_header.conf"
                headers = get_headers(os.path.join(config_dir, headers_file), args.username, args.password)
                timeout = int(args.timeout) if args.timeout else 300
                
                logger.info("Prober part started")
                results = []
                
                # Multi threading part to call prober
                with concurrent.futures.ThreadPoolExecutor() as executor:
                    futures = {executor.submit(call_endpoint_worker, endpoint, value, headers, timeout=timeout): endpoint for endpoint, value in endpoints.items()}
                    thread_start_time = time.time()
                    logger.info(f"All Prober threads submitted: {time.ctime(thread_start_time)}")  # Indicate submission complete
                    
                    for future in concurrent.futures.as_completed(futures):
                        try:
                            result = future.result()
                            results.append(result)
                        except Exception as e:
                            # Log the error, including the endpoint that failed
                            logger.info(f"Error calling endpoint {futures[future]}: {e}")
                
                thread_end_time = time.time()
                
                logger.info(f"All threads completed: {time.ctime(thread_end_time)}")
                total_thread_time = thread_end_time - thread_start_time
                logger.info(f"Prober multithread execution time: {total_thread_time:.4f} seconds")
                
                # Checking for errors
                has_errors = any(result["status_code"] in (-1, -2) for result in results)
                
                # Format the results for the message and email
                temp = endpoints_file.replace('.json', '')
                message_value = temp.replace('/tmp/', '')
                message = "Prober Results for:" + message_value + "\n"
                
                endpoint_maildata = f"<section style='border: thin solid black' align='center'><h3>Prober Results for {message_value}</h3><table border='1px solid black' align='center'>"
                endpoint_maildata += "<tbody><tr><td>&nbsp;Endpoint&nbsp;</td><td>&nbsp;Status Code&nbsp;</td><td>&nbsp;Elapsed Time (ms)&nbsp;</td></tr>"
                
                for result in results:
                    if result["status_code"] == 200:
                        endpoint_maildata += f"<tr><td>{result['endpoint']}</td><td style='background-color:#{greenColor};font-weight:bold;'>{result['status_code']}</td><td>{result['elapsed_time']}</td></tr>"
                    elif result["status_code"] == -1:
                        endpoint_maildata += f"<tr><td>{result['endpoint']}</td><td style='background-color:#{redColor};font-weight:bold;'>Error (-1)</td><td>{result['elapsed_time']}</td></tr>"
                    elif result["status_code"] == -2:
                        endpoint_maildata += f"<tr><td>{result['endpoint']}</td><td style='background-color:orange;font-weight:bold;'>Timeout (-2)</td><td>{result['elapsed_time']}</td></tr>"
                    else:
                        endpoint_maildata += f"<tr><td>{result['endpoint']}</td><td style='background-color:#{redColor};font-weight:bold;'>{result['status_code']}</td><td>{result['elapsed_time']}</td></tr>"
                
                endpoint_maildata += "</table><p>Status code legend:</p><ul><strong>200</strong>: Success, <strong>-1</strong>: Indicates an error, <strong>-2</strong>: Indicates a timeout.</strong></ul></section>"
                
                maildata += endpoint_maildata
                
                # Set email subject based on result
                if has_errors:
                    email_subject = 'Prober Completed with Errors'
                    logger.warning("Prober completed with errors. Check your email for details.")
                else:
                    email_subject = 'Prober Results'
                    logger.info("Prober completed successfully. Check your email for results.")
            else:
                email_subject = 'Probe Results'
            
            # Add cycle timing information
            cycle_end_time = time.time()
            logger.info(f"Cycle completed: {time.ctime(cycle_end_time)}")
            total_cycle_time = cycle_end_time - cycle_start_time
            logger.info(f"Total cycle execution time: {total_cycle_time:.4f} seconds")
            maildata += f"<div style='text-align:center'><strong>Total execution time: {total_cycle_time:.4f} seconds</strong></div>"
            
            # Send email with results if any data was generated and email is configured
            if maildata and args.email:
                text = maildata
                sendMail(sender, to_list, cc_list, email_subject)
            
            # ADDED: Log before sleep
            logger.info(f"Cycle completed. Sleeping for {args.interval} minutes before next run...")
            
            # ADDED: Sleep until next cycle
            time.sleep(args.interval * 60)
            
        except Exception as e:
            # ADDED: Error handling to keep pod running even if there's an error
            logger.error(f"Error in main execution loop: {e}")
            logger.info("Will retry in 60 seconds...")
            time.sleep(60)  # Sleep for 1 minute on error before retrying

# This is a constructor - it collects the files from cli
if __name__ == "__main__":
    main()