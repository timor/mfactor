((nil . ((eval . (setq org-publish-project-alist
		       `(("org-mfactor"
			  :base-directory ,(file-name-directory (or load-file-name buffer-file-name))
			  :publishing-directory
			  ,(concat (file-name-directory (or load-file-name buffer-file-name))
				   (file-name-as-directory "..")
				   (file-name-as-directory "html"))
                          :publishing-function org-html-publish-to-html
			  :recursive t
			  )
                         ("org-mfactor-static"
                          :base-directory ,(file-name-directory (or load-file-name buffer-file-name))
                          :base-extension "png\\|jpg\\|gif"
			  :publishing-directory
			  ,(concat (file-name-directory (or load-file-name buffer-file-name))
				   (file-name-as-directory "..")
				   (file-name-as-directory "html"))
                          :publishing-function org-publish-attachment
			  :recursive t
                          )
                         ("org" :components ("org-mfactor" "org-mfactor-static")))))
         (eval . (setq org-confirm-babel-evaluate (lambda (lang body) (not (string= lang "ditaa"))))))))
