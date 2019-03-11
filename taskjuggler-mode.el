;;; taskjuggler-mode.el --- Editing Taskjuggler Files

;; Copyright (C) 2008 by Stefan Kamphausen
;; Author: Stefan Kamphausen <http://www.skamphausen.de>
;; Keywords: user
;; This file is not part of Emacs.

;; This program is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING. If not, write to the Free
;; Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
;; 02111-1307, USA.


;;; Commentary:
;; This is a major mode which can be used to write files for
;; taskjuggler.  See http://www.taskjuggler.org for that scheduling
;; software. 
;; The version 2.4.1 of taskjuggler shipped with a tiny emacs lisp
;; file called taskjug.el.  From this I have taken the indentation
;; function.  All the rest was written from scratch, thus the new name
;; of the file: taskjuggler-mode.el
;; So it's kudos to Sean Dague (http://dague.net) for that older
;; version.  In his code he praised Scott Andrew Borton for writing a
;; very good tutorial on writing modes.
;;
;; Webpage: http://www.skamphausen.de/cgi-bin/ska/taskjuggler-mode

;;; FIXMEs
;; * The parser is called too often!
;; * The parser should be able to return several results in one call
;; * Cleanup repetion of task vs resources.
;; * Handling of multi-file documents (includes in the parser)
;; * What about buffer local variants of tasks and resources?
;; * support supplement

;;; TODO
;; * Context-sensitive highlighting, e.g. columns in reports
;; * Ad-Hoc highlighting of things in buffer, e.g. task names,
;;   resource names.
;; * Viewing of results, either using TaskjugglerUI or HTML-reports

;;; More Ideas
;; * Sorting of tasks in a context: by name, by priority
;; * Highlighting of priority according to value
;; * Validation of dependencies


(require 'smie)


(defgroup taskjuggler nil
  "TaskJuggler mode."
  :group 'languages)

(defvar taskjuggler-mode-hook nil)

(defconst taskjuggler-properties
  '("account"
    "copyright"
    "export"
    "flags"
    "include"
    "macro"
    "project"
    "resource"
    "scenario"
    "shift"
    "task")
  "Main building constructs of taskjuggler.
Used for font-lock.")

(defconst taskjuggler-attributes
  '("allocate"
    "allowredefinition"
    "alternative"
    "baseline"
    "booking"
    "complete"
    "cost"
    "credit"
    "currency"
    "currencyformat"
    "dailymax"
    "dailyworkinghours"
    "depends"
    "disabled"
    "duration"
    "efficiency"
    "effort"
    "enabled"
    "end"
    "endbuffer"
    "endcredit"
    "extend"
    "gapduration"
    "gaplength"
    "inherit"
    "journalentry"
    "label"
    "length"
    ;; load is abandoned should be warned!
    "limits"
    "mandatory"
    "maxeffort"
    "maxend"
    "maxpaths"
    "maxstart"
    "minend"
    "minslackrate"
    "minstart"
    "monthlymax"
    "note"
    "now"
    "numberformat"
    "overtime"
    "period"
    "persistent"
    "precedes"
    "priority"
    "projectid"
    "projectids"
    "projection"
    "purge"
    "rate"
    "reference"
    "responsible"
    "revenue"
    "sloppy"
    "scheduled"
    "scheduling"
    "select"
    "statusnote"
    "start"
    "startcredit"
    "startbuffer"
    "strict"
    "timeformat"
    "taskattributes"
    "taskprefix"
    "taskroot"
    "timezone"
    "timeformat"
    "timingresolution"
    "vacation"
    "weekdays"
    "weeklymax"
    "weekstartsmonday"
    "weekstartssunday"
    "workinghours"
    "yearlyworkingdays")
  "Attributes in taskjuggler.
Used for font-lock.")

(defconst taskjuggler-reports
  '("csvaccountreport"
    "csvresourcereport"
    "csvtaskreport"
    "htmlaccountreport"
    "htmlmonthlycalendar"
    "htmlresourcereport" 
    "htmltaskreport"
    "htmlstatusreport"
    "htmlweeklycalendar"
    "icalreport"
    "resourcereport"
    "taskreport"
    "xmlreport")
  "Report definition names.
Used for font-lock.")

(defconst taskjuggler-report-keywords
  '("accumulate"
    "barlabels"
    "caption"
    "celltext"
    "cellurl"
    "columns"
    "headline"
    "hideresource"
    "hideaccount"
    "hidecelltext"
    "hidecellurl"
    "hideresource"
    "hidetask"
    "loadunit"
    "properties"
    "rawhead"
    "rawstylesheet"
    "rawtail"
    "rollupaccount"
    "rollupresource"
    "rolluptask"
    "scenarios"
    "separator"
    "shorttimeformat"
    "showprojectids"
    "sortaccounts"
    "sortresources"
    "sorttasks"
    "subtitle"
    "subtitleurl"
    "title"
    "titleurl"
    "version")
  "Keywords in report definition.
Used for font-lock.")

(defconst taskjuggler-important
  '("milestone")
  "Keywords to highlight in warning face.")

(defconst taskjuggler-keywords-having-resource-arg
  '("allocate"
    "responsible"
    "alternative")
  "Keywords after which a resource may follow.  
Used when completing resources.")



(defvar taskjuggler-font-lock-keywords 
  (list
   (cons (regexp-opt taskjuggler-properties 'words) font-lock-function-name-face)
   (cons (regexp-opt taskjuggler-attributes 'words) font-lock-keyword-face)
   (cons (regexp-opt taskjuggler-reports 'words) font-lock-builtin-face)
   (cons (regexp-opt taskjuggler-report-keywords 'words) font-lock-constant-face)
   (cons (regexp-opt taskjuggler-important 'words) font-lock-warning-face)
   '("\\('\\w*'\\)" . font-lock-variable-name-face))
  "Default highlighting expressions for TASKJUG mode")

;;
;; SMIE based indentation engine
;;

(defcustom taskjuggler-indent-basic 2
  "Basic amount of indentation.
Default is 2. Use smie-indent-basic when nil"
  :type 'integer
  :group 'taskjuggler
  :safe (lambda (x) (and (integerp x) (> x 0)))
  )


(defconst taskjuggler-smie-grammar
  (smie-prec2->grammar
   (smie-bnf->prec2
    '(
      (props ("<KWD>" value)
             ("<KWD>" value "{" props "}")
             ("<LST>" attrs)
             (props "<KWD>" value)
             (props "<KWD>" value "{" props "}")
             (props "<LST>" attrs)
             )
      (attrs (attr)
             (attr "," attrs)
             )
      (attr  (value)
             (value "{" props "}")
             )
      (value)
      )
    '((left "<KWD>" "<LST>"))
    ))
  )


(defun taskjuggler-smie-rules (kind token)
  (pcase (cons kind token)
    (`(:elem . basic) taskjuggler-indent-basic)
    (`(,_ . ",") (smie-rule-separator kind))
    (`(:before . ,(or "{" "["))
     ;; reuse indentation of a first token to which "{" belongs to
     ;; (for example, reuse indend of "resource" or "task" keyword)
     (save-excursion
       (let (res)
         (while (null (setq res (smie-backward-sexp))))
         (pcase (nth 2 res)
           ("<KWD>"
            (goto-char (cadr res))
            (cons 'column (current-column)))
           (","
            (cons 'column (current-column)))
           (_
            nil)
           )
         )
       )
     )
    (`(:list-intro . "<KWD>") t)
    )
  )


(defconst taskjuggler-smie-token-hash
  #s(hash-table
     size 198
     test equal
     data (
           "account"               "<KWD>"
           "accountprefix"         "<KWD>"
           "accountreport"         "<KWD>"
           "accountroot"           "<KWD>"
           "active"                "<KWD>"
           "adopt"                 "<LST>"
           "aggregate"             "<KWD>"
           "alert"                 "<KWD>"
           "alertlevels"           "<LST>"
           "allocate"              "<LST>"
           "alternative"           "<LST>"
           "author"                "<KWD>"
           "auxdir"                "<KWD>"
           "balance"               "<KWD>"
           "booking"               "<LST>"
           "caption"               "<KWD>"
           "cellcolor"             "<KWD>"
           "celltext"              "<KWD>"
           "center"                "<KWD>"
           "charge"                "<KWD>"
           "chargeset"             "<LST>"
           "columns"               "<LST>"
           "complete"              "<KWD>"
           "copyright"             "<KWD>"
           "credits"               "<LST>"
           "currency"              "<KWD>"
           "currencyformat"        "<KWD>"
           "dailymax"              "<KWD>"
           "dailymin"              "<KWD>"
           "dailyworkinghours"     "<KWD>"
           "date"                  "<KWD>"
           "definitions"           "<LST>"
           "depends"               "<LST>"
           "details"               "<KWD>"
           "disabled"              "<KWD>"
           "duration"              "<KWD>"
           "efficiency"            "<KWD>"
           "effort"                "<KWD>"
           "effortdone"            "<KWD>"
           "effortleft"            "<KWD>"
           "email"                 "<KWD>"
           "enabled"               "<KWD>"
           "end"                   "<KWD>"
           "endcredit"             "<KWD>"
           "epilog"                "<KWD>"
           "export"                "<KWD>"
           "extend"                "<KWD>"
           "fail"                  "<KWD>"
           "flags"                 "<LST>"
           "fontcolor"             "<KWD>"
           "footer"                "<KWD>"
           "formats"               "<LST>"
           "gapduration"           "<KWD>"
           "gaplength"             "<KWD>"
           "halign"                "<KWD>"
           "hasalert"              "<LST>"
           "header"                "<KWD>"
           "headline"              "<KWD>"
           "height"                "<KWD>"
           "hideaccount"           "<KWD>"
           "hidejournalentry"      "<KWD>"
           "hidereport"            "<KWD>"
           "hideresource"          "<KWD>"
           "hidetask"              "<KWD>"
           "icalreport"            "<KWD>"
           "include"               "<KWD>"
           "inherit"               "<KWD>"
           "isactive"              "<KWD>"
           "ischildof"             "<KWD>"
           "isdependencyof"        "<LST>"
           "isdutyof"              "<LST>"
           "isfeatureof"           "<LST>"
           "isleaf"                "<KWD>"
           "ismilestone"           "<KWD>"
           "isongoing"             "<KWD>"
           "isresource"            "<KWD>"
           "isresponsibilityof"    "<KWD>"
           "istask"                "<KWD>"
           "isvalid"               "<KWD>"
           "journalattributes"     "<LST>"
           "journalentry"          "<KWD>"
           "journalmode"           "<KWD>"
           "leaveallowance"        "<LST>"
           "leaves"                "<LST>"
           "left"                  "<KWD>"
           "length"                "<KWD>"
           "limits"                "<KWD>"
           "listitem"              "<KWD>"
           "listtype"              "<KWD>"
           "loadunit"              "<KWD>"
           "macro"                 "<KWD>"
           "managers"              "<LST>"
           "mandatory"             "<KWD>"
           "maxend"                "<KWD>"
           "maximum"               "<KWD>"
           "maxstart"              "<KWD>"
           "milestone"             "<KWD>"
           "minend"                "<KWD>"
           "minimum"               "<KWD>"
           "minstart"              "<KWD>"
           "monthlymax"            "<KWD>"
           "monthlymin"            "<KWD>"
           "navigator"             "<KWD>"
           "newtask"               "<KWD>"
           "nikureport"            "<KWD>"
           "note"                  "<KWD>"
           "now"                   "<KWD>"
           "number"                "<KWD>"
           "numberformat"          "<KWD>"
           "onend"                 "<KWD>"
           "onstart"               "<KWD>"
           "opennodes"             "<LST>"
           "outputdir"             "<KWD>"
           "overtime"              "<KWD>"
           "period"                "<KWD>"
           "persistent"            "<KWD>"
           "precedes"              "<KWD>"
           "priority"              "<KWD>"
           "project"               "<KWD>"
           "projectid"             "<KWD>"
           "projectids"            "<LST>"
           "projection"            "<KWD>"
           "prolog"                "<KWD>"
           "purge"                 "<KWD>"
           "rate"                  "<KWD>"
           "rawhtmlhead"           "<KWD>"
           "reference"             "<KWD>"
           "remaining"             "<KWD>"
           "replace"               "<KWD>"
           "reportprefix"          "<KWD>"
           "resource"              "<KWD>"
           "resourceattributes"    "<LST>"
           "resourceprefix"        "<KWD>"
           "resourcereport"        "<KWD>"
           "resourceroot"          "<KWD>"
           "resources"             "<LST>"
           "responsible"           "<LST>"
           "richtext"              "<KWD>"
           "right"                 "<KWD>"
           "rollupaccount"         "<KWD>"
           "rollupresource"        "<KWD>"
           "rolluptask"            "<KWD>"
           "scale"                 "<KWD>"
           "scenario"              "<KWD>"
           "scenarios"             "<LST>"
           "scenariospecific"      "<KWD>"
           "scheduled"             "<KWD>"
           "scheduling"            "<KWD>"
           "schedulingmode"        "<KWD>"
           "select"                "<KWD>"
           "selfcontained"         "<KWD>"
           "shift"                 "<KWD>"
           "shifts"                "<LST>"
           "shorttimeformat"       "<KWD>"
           "sloppy"                "<KWD>"
           "sortaccounts"          "<LST>"
           "sortjournalentries"    "<LST>"
           "sortresources"         "<LST>"
           "sorttasks"             "<LST>"
           "start"                 "<KWD>"
           "startcredit"           "<KWD>"
           "status"                "<KWD>"
           "statussheet"           "<KWD>"
           "statussheetreport"     "<KWD>"
           "strict"                "<KWD>"
           "summary"               "<KWD>"
           "supplement"            "<KWD>"
           "tagfile"               "<KWD>"
           "task"                  "<KWD>"
           "taskattributes"        "<LST>"
           "taskprefix"            "<KWD>"
           "taskreport"            "<KWD>"
           "taskroot"              "<KWD>"
           "text"                  "<KWD>"
           "textreport"            "<KWD>"
           "timeformat"            "<KWD>"
           "timeformat1"           "<KWD>"
           "timeformat2"           "<KWD>"
           "timeoff"               "<KWD>"
           "timesheet"             "<KWD>"
           "timesheetreport"       "<KWD>"
           "timezone"              "<KWD>"
           "timingresolution"      "<KWD>"
           "title"                 "<KWD>"
           "tooltip"               "<KWD>"
           "tracereport"           "<KWD>"
           "trackingscenario"      "<KWD>"
           "treelevel"             "<KWD>"
           "vacation"              "<LST>"
           "warn"                  "<KWD>"
           "weeklymax"             "<KWD>"
           "weeklymin"             "<KWD>"
           "weekstartsmonday"      "<KWD>"
           "weekstartssunday"      "<KWD>"
           "width"                 "<KWD>"
           "work"                  "<KWD>"
           "workinghours"          "<LST>"
           "yearlyworkingdays"     "<KWD>"
           )
     )
  )


(defun taskjuggler-smie-forward-token ()
  (let ((token (smie-default-forward-token)))
    (gethash token taskjuggler-smie-token-hash token)))


(defun taskjuggler-smie-backward-token ()
  (let ((token (smie-default-backward-token)))
    (gethash token taskjuggler-smie-token-hash token)))


;; Parser

(defvar taskjuggler-tasks ()
  "A list of all tasks found in the buffer.

The items on this list are lists of the form

  (\"path.of.task\" hierarchy \"Description of Task\"
")

(defvar taskjuggler-resources ()
  "A list of all resources found in the buffer.

The items on this list are lists of the form

  (\"path.of.resource\" hierarchy \"Description of Resource\"
")

(defun taskjuggler-make-path (path)
  "Takes a list argument PATH, returns a string with list elements
  joined with a dot."
  (when path
    (mapconcat 'identity (reverse path) ".")))

(defvar taskjuggler-name-re "[a-zA-z_][a-zA-Z0-9_]+"
  "RegExp for valid names in taskjuggler.")


(defun taskjuggler-parser (&optional limit request verbose)
  "The core of this mode.  Parses a taskjuggler file.

LIMIT can be used if parsing should end at that position.  

Request is one of the following:
nil           return task tree
'task-tree    return task tree
'hierarchy    return the hierarchy at LIMIT
'context-path return the (task)-context path at LIMIT
'path-as-list return the (task)-context at LIMIT as a list
"
  (let ((lim (or limit (point-max)))
        (path ())
        (hierarchy 0)
        (task-tree ())
        (res-tree ())
        (task-hierarchy 0)
        (res-hierarchy 0))
    (save-excursion 
      (when verbose (message "Limit: %s" lim))
      (goto-char (point-min))
      (while (and (not (eobp))
                  (< (point) lim))
        (when (looking-at "{")
          (setq hierarchy (1+ hierarchy))
          (when verbose (message "hierarchy+ %d" hierarchy)))
        (when (looking-at "}")
          (when (= hierarchy task-hierarchy)
            (setq path (cdr path))
            (setq task-hierarchy (1- task-hierarchy)))
          (when (= hierarchy res-hierarchy)
            (setq path (cdr path))
            (setq res-hierarchy (1- res-hierarchy)))
          (setq hierarchy (1- hierarchy))
          (when verbose (message "hierarchy- %d" hierarchy)))
        (cond
         ;; comments
         ((looking-at "#")
          (when verbose (message "Comment"))
          (while (not (eolp)) (forward-char 1)))
         ((looking-at "/\\*")
          (search-forward "*/"))
         ((looking-at (concat
                       "task\\s-+\\("
                       taskjuggler-name-re
                       "\\)\\s-+\"\\([^\"]+\\)\"\\s-*{"))
          (setq task-hierarchy (1+ hierarchy))
          (setq path (cons (match-string-no-properties 1) path))
          (when verbose (message "task(%d) %s" task-hierarchy 
                                 (taskjuggler-make-path path)))
          (setq task-tree
                (cons (list (taskjuggler-make-path path)
                            task-hierarchy
                            (match-string-no-properties 1)
                            (match-string-no-properties 2))
                      task-tree))
          (goto-char (match-end 0))
          (forward-char -2))
         ((looking-at (concat
                       "resource\\s-+\\("
                       taskjuggler-name-re
                       "\\)\\s-+\"\\([^\"]+\\)\"\\s-*{"))
          (setq res-hierarchy (1+ hierarchy))
          (setq path (cons (match-string-no-properties 1) path))
          (when verbose (message "resource(%d) %s" res-hierarchy 
                                 (taskjuggler-make-path path)))
          (setq res-tree
                (cons (list (taskjuggler-make-path path)
                            res-hierarchy
                            (match-string-no-properties 1)
                            (match-string-no-properties 2))
                      res-tree))
          (goto-char (match-end 0))
          (forward-char -2)))
        (forward-char 1)
        ))
    (cond
     ((or (null request)
          (eq request 'tasktree))
      (reverse task-tree))
     ((eq request 'resourcetree)
      (reverse res-tree))
     ((eq request 'path-as-list)
      path)
     ((eq request 'context-path)
      (taskjuggler-make-path path))
     ((eq request 'hierarchy)
      hierarchy)
     (t (error "Wrong request specifier %s" request)))))

(defun taskjuggler-rescan-buffer ()
  "Rescan the current buffer for tasks and resources."
  (interactive)
  (taskjuggler-rescan-tasks)
  (taskjuggler-rescan-resources))

(defun taskjuggler-rescan-tasks ()
  "Rescan current buffer for task definitions."
  (interactive)
  (setq taskjuggler-tasks (taskjuggler-parser nil 'tasktree)))

(defun taskjuggler-rescan-resources ()
  "Rescan current buffer for resource definitions."
  (interactive)
  (setq taskjuggler-resources (taskjuggler-parser nil 'resourcetree)))

(defun taskjuggler-current-context-path ()
  "Find the current task context at point."
  (interactive)
  (taskjuggler-parser (point) 'context-path))

(defun taskjuggler-read-up-hier-at-point ()
  "Read the number of exclamation marks in current logical expression."
  (let ((excl-count 0)
        (start-pos (point)))
    (save-excursion
      (forward-char -1)
      (while (not (looking-at "\\s-"))
        (forward-char -1))
      (while (< (point) start-pos)
        (when (looking-at "!")
          (setq excl-count (1+ excl-count)))
        (forward-char 1)))
    excl-count))


(defun taskjuggler-current-hierarchy ()
  "Calculate task hierarchy at point."
  (interactive)
  (taskjuggler-parser (point) 'hierarchy))

(defun taskjuggler-make-dependeny-path (target-task-path context-path)
  "Compute the relative path from CONTEXT-PATH to TARGET-TASK-PATH.

Examples:

TARGET-TASK-PATH  CONTEXT-PATH    RESULT
a.b.c             (a b)           !c
a.b.c             (d e f)         !!!a.b.c
"
  (let ((l1 (split-string target-task-path  "\\."))
        (l2 (split-string context-path "\\."))
        (continue-flag t))
    (while (and l1 l1 continue-flag)
      (setq li1 (first l1))
      (setq li2 (first l2))
      (if (not (string-equal li1 li2))
          (setq continue-flag nil)
        (progn
          (setq l1 (cdr l1))
          (setq l2 (cdr l2)))))

    (concat 
     (make-string (length l2) ?\!)
     (mapconcat 'identity l1 "."))))

(defun taskjuggler-insert-dependency ()
  "Insert the keyword depend and a task with completion.

The completion of tasks is global but the resulting path to be
inserted is calculated relative to the current context.  See
`taskjuggler-make-dependeny-path' for that."

  (interactive)
  (when (not taskjuggler-tasks)
    (taskjuggler-rescan-tasks))
  (let ((completion 
         (completing-read
          "Depend on Task: "
          (mapcar 'first taskjuggler-tasks))))
    (when completion
      (insert "depends "
              (taskjuggler-make-dependeny-path 
               completion
               (taskjuggler-current-context-path))))))

(defun taskjuggler-insert-resource ()
  "Insert a resource at point with completion and context.

If a keyword having a resource argument is found in the current line
before point the user will be asked for the resource only and that
will be inserted.  Otherwise this function asks for the keyword to use
\(again with completion).  See also:
`taskjuggler-keywords-having-resource-arg'." 
  (interactive)
  (when (not taskjuggler-resources)
    (taskjuggler-rescan-resources))
  (let ((pos (point)))
      (unless 
          (save-excursion
            (beginning-of-line)
            (re-search-forward
               (regexp-opt 
                taskjuggler-keywords-having-resource-arg
                'word) 
               pos t))
        (insert (completing-read
                 "Insert Keyword: "
                 taskjuggler-keywords-having-resource-arg))
        (insert " ")))
  (insert (completing-read
            "Resource: " 
            (mapcar #'(lambda (elm)
                        (last (split-string (first elm)  "\\.")))
                    taskjuggler-resources)
            nil t)))

;; Earlier versions tried to complete word at point and only complete
;; the available tasks depending on current context and number of
;; exclamation marks.  My brain hurts...
;; (defun taskjuggler-make-task-completion-table (context hierarchy)
;;   (let ((substr-size (length context)))
;;   (remove-if 
;;    #'null
;;    (mapcar 
;;     #'(lambda (elm) 
;;         (message "Hier %s Elm%s" hierarchy elm)
;;         (if (and (= (second elm) (1+ hierarchy))
;;                  (or (not context)
;;                      (string= (substring
;;                                (first elm) 0 (min (length (first elm))
;;                                                   substr-size)) 
;;                           context)))
;;             (third elm)
;;           nil))
;;     taskjuggler-tasks))))
;; (defun taskjuggler-complete-dependency ()
;;   "Allow completion of dependencies."
;;   (interactive)
;;   (let* ((current-context (taskjuggler-current-context-list))
;;          (up-hierarchy    (taskjuggler-read-up-hier-at-point))
;;          (current-hier    (taskjuggler-current-hierarchy))
;;          (completion-path (taskjuggler-make-path
;;                            (nthcdr up-hierarchy current-context)))
;;          (end (point))
;;          (beg (save-excursion
;;                 (when (looking-at "[ \t\n!]")
;;                   (forward-char -1))
;;                 (while (not (looking-at "[ \t\n!]"))
;;                   (forward-char -1))
;;                 (1+ (point))))
;;          (word-at-point (buffer-substring-no-properties beg end)))
;;     (message "WAP: %s CuHie %s UpHi %s %s" word-at-point current-hier
;;              up-hierarchy (taskjuggler-make-task-completion-table
;;                       completion-path (- current-hier up-hierarchy))
;;              )))
;;     (completing-read "Task: "
;;                      (taskjuggler-make-task-completion-table
;;                       completion-path (- current-hier up-hierarchy)) 
;;                      nil t word-at-point)))

;; (defun taskjuggler-complete-dependency ()
;;   "Allow completion of dependencies."
;;   (interactive)
;;   (let* ((current-context (taskjuggler-current-context-list))
;;          (up-hierarchy    (taskjuggler-read-up-hier-at-point))
;;          (current-hier    (taskjuggler-current-hierarchy))
;;          (completion-path (taskjuggler-make-path
;;                            (nthcdr up-hierarchy current-context)))
;;     )
;;     (message "Context %s  CompPath %s UpHier %d ThHier %d"
;;              current-context completion-path up-hierarchy current-hier)))
;;          (comp (completing-read 
;;                 "Task: " (taskjuggler-make-task-completion-table
;;                           completion-path current-hier))))))

;; Inserting code
(define-skeleton taskjuggler-insert-task 
  "Insert a new task."
  "Name of the task: "
  "task " str " \"" _ "\" {\n\n}")
(define-skeleton taskjuggler-insert-resource-def 
  "Insert a new resource."
  "Name of the resource: "
  "resource " str " \"" _ "\" {\n\n}")

;; Compile
(defun taskjuggler-build-compile-command (buffer &optional args)
  (concat "taskjuggler "
          (cond 
           ((listp args) (mapconcat 'identity args " "))
           ((stringp args) args))
          " "
          (buffer-file-name buffer)))

(defun taskjuggler-compile ()
  (interactive)
  (let ((cmd (taskjuggler-build-compile-command (current-buffer))))
    (compile cmd)))

(defun taskjuggler-check-syntax ()
  (interactive)
  (let ((cmd (taskjuggler-build-compile-command (current-buffer) "-s")))
    (compile cmd)))

;; Map
(defvar taskjuggler-mode-map nil
  "Keymap used in taskuggler-mode.")

(when (not taskjuggler-mode-map)
  (setq taskjuggler-mode-map (make-keymap))
  (define-key taskjuggler-mode-map [(control j)] 'newline-and-indent)
  (define-key taskjuggler-mode-map [(control c) (control d)] 'taskjuggler-insert-dependency)
  (define-key taskjuggler-mode-map [(control c) (control c)] 'taskjuggler-compile)
  (define-key taskjuggler-mode-map [(control c) (control s)] 'taskjuggler-check-syntax)
  (define-key taskjuggler-mode-map [(control c) (r)]         'taskjuggler-rescan-buffer)
  (define-key taskjuggler-mode-map [(control c) (control r)] 'taskjuggler-insert-resource)
  (define-key taskjuggler-mode-map [(control c) (i) (t)] 'taskjuggler-insert-task)
  (define-key taskjuggler-mode-map [(control c) (i) (r)] 'taskjuggler-insert-resource-def))

;; Syntax

(defvar taskjuggler-mode-syntax-table
  (let ((st (make-syntax-table)))
    ;; This is added so entity names with underscores can be more easily parsed
    (modify-syntax-entry ?_ "w"  st)
    ;; Comments have three different syntaxes
    (modify-syntax-entry ?#  "<" st)    ; shell-style comments
    (modify-syntax-entry ?/ ". 124" st) ; C-style comments both
    (modify-syntax-entry ?* ". 23b" st) ; singe- and multi-line
    (modify-syntax-entry ?\n ">" st)    ; comment endings for
    (modify-syntax-entry ?\r ">" st)    ; single-line styles
    ;; Strings have three different syntaxes
    ;; http://taskjuggler.org/tj3/manual/The_TaskJuggler_Syntax.html#STRING
    (modify-syntax-entry ?\" "\"" st)   ; double quote strings
    (modify-syntax-entry ?\' "\"" st)   ; single quote strings
    ;; multiline strings syntax is too complex for syntax tables, so
    ;; it is parsed with taskjuggler-syntax-propertize-function
    st)
  "Syntax table to use for taskjuggler mode.")


(defun taskjuggler-syntax-propertize-function (start end)
  (goto-char start)
  (while (and (< (point) end)
              (re-search-forward "\\(-\\)8<-$\\|^\\s *->8\\(-\\)" end t))
    (cond
     ((match-beginning 1)
      (save-excursion
        (let ((ppss (syntax-ppss
                     (1- (match-beginning 1)))))
          ;; match -8<- only before end of line, but only outside
          ;; strings and comments
          (if (and (null (nth 3 ppss))
                   (null (nth 4 ppss)))
              (put-text-property
               (match-beginning 1)
               (match-end 1)
               'syntax-table
               '(15))))))
     ((match-beginning 2)
      (save-excursion
        ;; match ->8- only inside generic string near bol
        (if (eq t (nth 3 (syntax-ppss (1- (point)))))
            (put-text-property
             (match-beginning 2)
             (match-end 2)
             'syntax-table
             '(15))))))))


(define-derived-mode taskjuggler-mode prog-mode
  "TaskJuggler"
  "Major mode for editing TaskJuggler input files.

\\{taskjuggler-mode-map}"

  :syntax-table taskjuggler-mode-syntax-table
  ;:group  ; FIXME
  :after-hook taskjuggler-mode-hook

  (setq-local syntax-propertize-function
              #'taskjuggler-syntax-propertize-function)

  ;; comment syntax is defined in syntax table
  (setq-local comment-start "# ")
  (setq-local comment-start-skip "\\(//+\\|#+\\|/\\*+\\)[[:space:]]*")
  (setq-local comment-end "")
  ;;(setq-local comment-end-skip "[[:space:]]*\\**/")

  (use-local-map taskjuggler-mode-map)

  ;; Setting up Font Lock mode
  (setq-local font-lock-defaults '(taskjuggler-font-lock-keywords nil t nil nil))

  ;; Setup SMIE indentation engine
  (smie-setup taskjuggler-smie-grammar #'taskjuggler-smie-rules
              :forward-token 'taskjuggler-smie-forward-token
              :backward-token 'taskjuggler-smie-backward-token)
  )


(add-to-list 'auto-mode-alist '("\\.tjp\\'" . taskjuggler-mode))
(add-to-list 'auto-mode-alist '("\\.tji\\'" . taskjuggler-mode))
(add-to-list 'auto-mode-alist '("\\.tjsp\\'" . taskjuggler-mode))


(provide 'taskjuggler-mode)
