function newassignment --description 'Create new LaTeX assignment from immutable template'
    set -l template_file ~/.config/latex/assignment_template.tex
    if not test -f $template_file
        echo "Template not found: $template_file"
        return 1
    end
    
    read -P "Course code (e.g. MATH 2303): " course
    read -P "Semester (e.g. Fall 2025): " semester
    read -P "Due date (e.g. September 23, 2025): " due
    read -P "Assignment name (e.g. Assignment 1): " assignment
    read -P "Author (leave empty for system user): " author
    
    if test -z "$author"
        set -l gitname (git config user.name 2>/dev/null)
        if test -n "$gitname"
            set author $gitname
        else
            set author $USER
        end
    end
    
    # sanitize filename: spaces -> underscores, remove unsafe chars
    set -l base (string replace ' ' '_' -- $assignment)
    set -l base (string replace -r '[^[:alnum:]_-]' '' -- $base)
    if test -z "$base"
        echo "Resulting filename empty after sanitization; choose a different assignment name."
        return 1
    end
    
    # ensure it's created in the current working directory
        set -l outfile "$PWD/$base.tex"
    
        if test -f $outfile
                read -P "'$outfile' exists — overwrite? [y/N]: " yn
                if test "$yn" != "y" -a "$yn" != "Y"
                        echo "Aborted."
                        return 1
                end
        end
    
        # copy template (do not modify original)
        cp $template_file $outfile
    
        # helper: escape for sed replacement
        function _esc
                printf "%s" "$argv[1]" | sed 's/[\/&]/\\&/g'
        end
    
        set -l esc_course (_esc "$course")
        set -l esc_assignment (_esc "$assignment")
        set -l esc_author (_esc "$author")
        set -l esc_due (_esc "$due")
        set -l esc_semhdr (_esc "$semester \\ \\ Due: $due")
        set -l esc_coursehdr (_esc "$course \\ \\ $assignment")
    
        # Replace longer/unique placeholders first to avoid overlap
        sed -i \
              -e "s/SEMester_and_due_PLACEHOLDER/$esc_semhdr/g" \
              -e "s/COURSE_HEADER_PLACEHOLDER/$esc_coursehdr/g" \
              -e "s/ASSIGNMENT_TITLE_PLACEHOLDER/$esc_assignment/g" \
              -e "s/AUTHOR_PLACEHOLDER/$esc_author/g" \
              -e "s/COURSE_PLACEHOLDER/$esc_course/g" \
              -e "s/DUE_PLACEHOLDER/$esc_due/g" \
              -- $outfile
    
        echo "Created: $outfile"
    
        # open in $EDITOR if set, otherwise nvim
        if test -n "$EDITOR"
                $EDITOR $outfile
        else
                nvim $outfile
        end
end
