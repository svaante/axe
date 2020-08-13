;;; axe-logs  --- Functions for working with AWS logs -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:
(require 'json)
(require 'thingatpt)
(require 'axe-api)
(require 'axe-util)
(require 'axe-buffer-mode)

;;; API Functions

(cl-defun axe-logs--describe-log-groups (success &key next-token prefix limit)
  "Request log groups using PREFIX and NEXT-TOKEN.

Provide results to callback function SUCCESS on comletion.  Both
can be specified nil to omit."
  (axe-api-request
   (axe-api-endpoint 'logs axe-region)
   'logs
   (lambda (response) (funcall success (json-read-from-string response)))
   "POST"
   :headers '(("Content-Type" . "application/x-amz-json-1.1")
	      ("X-Amz-Target" . "Logs_20140328.DescribeLogGroups"))
   :request-payload (trim-and-encode-alist
		     (list (cons "limit" limit)
			   (cons "nextToken" next-token)
			   (cons "logGroupNamePrefix" prefix)))))

(cl-defun axe-logs--describe-log-streams (success log-group-name &key next-token descending limit log-stream-name-prefix order-by)
  "Describe log streams for LOG-GROUP-NAME."
  (axe-api-request
   (axe-api-endpoint 'logs axe-region)
   'logs (lambda (response) (funcall success (json-read-from-string response))) "POST"
   :headers '(("Content-Type" . "application/x-amz-json-1.1")
	      ("X-Amz-Target" . "Logs_20140328.DescribeLogStreams"))
   :request-payload (trim-and-encode-alist
		     (list (cons "logGroupName" log-group-name)
			   (cons "descending" descending)
			   (cons "limit" limit)
			   (cons "logStreamNamePrefix" log-stream-name-prefix)
			   (cons "nextToken" next-token)
			   (cons "orderBy" order-by)))))

(cl-defun axe-logs--get-log-events (success log-group-name log-stream-name &key next-token end-time limit start-from-head start-time)
  "Get log events for stream with name LOG-STREAM-NAME of group LOG-GROUP-NAME"
  (axe-api-request
    (axe-api-endpoint 'logs axe-region)
   'logs (lambda (response) (funcall success (json-read-from-string response))) "POST"
   :headers '(("Content-Type" . "application/x-amz-json-1.1")
	      ("X-Amz-Target" . "Logs_20140328.GetLogEvents"))
   :request-payload (trim-and-encode-alist
		     (list (cons "logGroupName" log-group-name)
			   (cons "logStreamName" log-stream-name)
			   (cons "nextToken" next-token)
			   (cons "endTime" end-time)
			   (cons "limit" limit)
			   (cons "startFromHead" start-from-head)
			   (cons "startTime" start-time)))))

;;; Insert functions

(defun axe-logs--insert-log-group (log-group)
  "Insert formatted text for LOG-GROUP into current buffer."
  (let ((inhibit-read-only t)
	(log-group-name (alist-get 'logGroupName log-group))
	(size (file-size-human-readable (alist-get 'storedBytes log-group)))
	(creation-time (format-time-string "%F %T" (seconds-to-time (/ (alist-get 'creationTime log-group) 1000)))))
    (insert (propertize (format "%s %8s %s\n" creation-time size log-group-name) 'log-group log-group))))

(defun axe-logs--insert-log-event (log-event)
  "Insert formatted text for LOG-EVENT into current buffer."
  (let ((inhibit-read-only t)
	(message (alist-get 'message log-event))
	(timestamp (format-time-string "%F %T" (seconds-to-time (/ (alist-get 'timestamp log-event) 1000)))))
    (insert (propertize (format "%s %s\n" timestamp message) 'log-event log-event))))

;;; List buffers

;;;###autoload
(defun axe-logs-describe-log-groups (prefix)
  "Opens a new buffer and displays all log groups.
If PREFIX is not nil, it is used to filter by log group name
prefix.  May result in multiple API calls.  If that is the case
then subsequent results may take some time to load and
displayed."
  (interactive "sPrefix: ")
  (let ((prefix (if (equal "" prefix) nil prefix))
	(limit 1))
    (axe-buffer-list
     'axe-logs--describe-log-groups
     "*axe-log-groups*"
     (lambda (response) (alist-get 'logGroups response))
     (list :prefix prefix :limit limit)
     (lambda (map)
       (define-key map (kbd "l") 'axe-logs--latest-log-stream-at-point)
       map)
     'axe-logs--insert-log-group
     (lambda (response) (alist-get 'nextToken response))
     :auto-follow t
     :auto-follow-delay 0.1)))

;;;###autoload
(cl-defun axe-logs-get-log-events (log-group-name log-stream-name &key auto-follow (auto-follow-delay 5.0))
  "Display log events for stream with name LOG-STREAM-NAME in log group LOG-GROUP-NAME.
Specifying FOLLOW-NEXT as non-nil will start the buffer in follow
mode.  In follow mode the next API request will automatically be
executed after FOLLOW-DELAY seconds (default 5 seconds)."
  (interactive "sLog Group Name:
sLog Stream Name: ")
  (axe-buffer-list
   'axe-logs--get-log-events
   (format "*axe-log-stream:%s*" log-stream-name)
   (lambda (response) (alist-get 'events response))
   (list log-group-name log-stream-name)
   ()
   'axe-logs--insert-log-event
   (lambda (response)
     (alist-get 'nextForwardToken response))
   :auto-follow auto-follow
   :auto-follow-delay auto-follow-delay))

(defun axe-logs--log-group-name-at-point ()
  "Get the log group name at point."
  (let ((log-group (get-text-property (point) 'log-group)))
    (if (null log-group) (thing-at-point 'symbol) (alist-get 'logGroupName log-group))))

;;;###autoload
(defun axe-logs--latest-log-stream-at-point ()
  "Open the log stream defined at the current  point.
First checks for text property log-group otherwise uses the text
at point in the buffer."
  (interactive)
  (let ((log-group-name (axe-logs--log-group-name-at-point)))
    (axe-logs--describe-log-streams
     (lambda (response)
       (let ((log-stream-name (alist-get 'logStreamName (elt (alist-get 'logStreams response) 0))))
	 (axe-logs-get-log-events log-group-name log-stream-name)))
     log-group-name
     :limit 1
     :descending t
     :order-by "LastEventTime")))

(provide 'axe-logs)
;;; axe-logs.el ends here