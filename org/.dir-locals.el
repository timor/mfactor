((nil . ((eval . (setq org-publish-project-alist
		       `(("org-mfactor"
			  :base-directory ,(file-name-directory (or load-file-name buffer-file-name))
			  :publishing-directory
			  ,(concat (file-name-directory (or load-file-name buffer-file-name))
				   (file-name-as-directory "..")
				   (file-name-as-directory "html"))
			  :recursive t
			  :publishing-function org-publish-org-to-html
			  )))))))
