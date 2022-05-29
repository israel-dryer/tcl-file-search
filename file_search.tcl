##################################################################################
#   ___         ___     __   ___       __   __       
#  |__  | |    |__     /__` |__   /\  |__) /  ` |__| 
#  |    | |___ |___    .__/ |___ /~~\ |  \ \__, |  | 
#
##################################################################################
#   Author      :   Israel Dryer
#   Updated     :   2022-05-29
#   Description :   Small hobby project to learn TCL & TK
#
#   Other than the GUI interface; this project uses threaded message passing
#   to communicate between the GUI and the worker thread that is handling the
#   searching process. The worker thread cannot update the GUI directly, but
#   it can pass a script to the main thread which gets added to the end of the
#   main threads event queue; which is then executed. This helps me to keep the
#   GUI mostly interactive; though with significant numbers of results, the GUI
#   will still show some lag due to the number of records being inserted into
#   the treeview. A potential fix may be to paginate the results. But, that is
#   another project. I also decided to avoid using shared variables via the
#   tsv package. This would have worked, but it was just easier to send a message
#   to the worker thread.

package require Tk
package require Thread

# global variables
set tid [thread::id]
set path [pwd]
set pattern {}
set type 1
set count "Count of results: 0"


namespace eval Worker {

    namespace export worker

    # setup worker thread for handling search requests
    set worker [thread::create {
        
        package require fileutil::traverse
        
            proc matchesPattern {filename} {
                return [regexp [tsv::get app pattern] $filename]
            }
            
            proc getInsertScript {filename} {
                if {[string length $filename]} {
                    set script ".c.tv insert {} end -values \{"
                    set script [string cat $script " " [file tail $filename]]
                    set script [string cat $script " " [file mtime $filename]]
                    set script [string cat $script " " [file extension $filename]]
                    set script [string cat $script " " [file size $filename]]
                    set script [string cat $script " " [file normalize $filename]]
                    set script [string cat $script " \}"]
                    return $script
                }
                return 0
            }		
        
            proc fileSearch {baseDir tid pattern} {
                fileutil::traverse T $baseDir -prefilter "file readable"
                set count 0
                T foreach f {
                    if {[string match $pattern $f]} {
                        incr count
                        set script [getInsertScript $f]
                        if {$script != 0} {
                            # send message to create the table row
                            after [expr int(rand() * 1000)] [thread::send -async $tid $script]
                            # send the message to update the result count
                            set numscript "variable count \{Count of results: $count\}"
                            thread::send -async $tid $numscript
                        }
                    }
                }
                T destroy
            }
        thread::wait   
        }	
    ]
}


namespace eval GUI {
    
    # create application window in main thread
    wm title . "File Search Engine"
    wm geometry . "1600x1000"
    
    pack [ttk::frame .c -padding 10] -fill both -expand 1
    
    # upper form container
    pack [ttk::labelframe .c.lf -text "Complete the form to begin your search" -padding 10] -side top -fill x -pady 10
    grid [ttk::label .c.lf.l1 -text "Path"] -row 0 -column 0 -sticky w
    grid [ttk::label .c.lf.l2 -text "Term"] -row 1 -column 0 -sticky w
    grid [ttk::label .c.lf.l3 -text "Type"] -row 2 -column 0 -sticky w
    grid [ttk::entry .c.lf.path_entry -textvariable path] -row 0 -column 1 -columnspan 3 -sticky ew -padx 10
    grid [ttk::entry .c.lf.term_entry -textvariable pattern] -row 1 -column 1 -columnspan 3 -sticky ew -padx 10
    grid [ttk::radiobutton .c.lf.contains -text "Contains" -variable type -value 1] -row 2 -column 1 -sticky w  -padx 10
    grid [ttk::radiobutton .c.lf.startswith -text "StartsWith" -variable type -value 2] -row 2 -column 2 -sticky w
    grid [ttk::radiobutton .c.lf.endswith -text "EndsWith" -variable type -value 3] -row 2 -column 3 -sticky w -padx 10
    grid [ttk::label .c.lf.count -textvariable count] -row 2 -column 4 -sticky e -padx 10
    grid [ttk::button .c.lf.browse -text "Browse" -command GUI::onClickBrowseButton] -row 0 -column 4 -sticky ew
    grid [ttk::button .c.lf.search -text "Search" -command GUI::onClickSearchButton] -row 1 -column 4 -sticky ew
    grid columnconfigure .c.lf 3 -weight 1
    foreach row [list 0 1 2 3] { grid rowconfigure .c.lf $row -pad 10 }
    
    # lower treeview
    pack [ttk::treeview .c.tv -show headings -columns [list 1 2 3 4 5]] -side bottom -fill both -expand 1
    
    # heading configuration
    .c.tv heading 1 -text "Name" -anchor w
    .c.tv heading 2 -text "Modified" -anchor w
    .c.tv heading 3 -text "Type" 
    .c.tv heading 4 -text "Size" 
    .c.tv heading 5 -text "Path" -anchor w
    
    # column configuration
    .c.tv column 1 -stretch 0 -width 400
    .c.tv column 2 -stretch 0 -width 150
    .c.tv column 3 -stretch 0 -width 120 -anchor center
    .c.tv column 4 -stretch 0 -width 120 -anchor e
    .c.tv column 5 -stretch 1 -width 120 
    
    # Configure default row height on Tree view style
    ttk::style configure Treeview -rowheight 30
    
    # Browse button callback
    proc onClickBrowseButton {} {
        set filepath [tk_chooseDirectory -parent . -title "Search Path" -initialdir "." -mustexist 1]
        if {[regexp . $filepath]} {
                set ::path $filepath
            } else { return }
    }
    
    # Search button callback
    proc onClickSearchButton {} {
        resetTreeview
        getSearchPattern
        variable count "Count of results: 0"
        set script [join [list fileSearch $::path $::tid $::pattern] " "]
        thread::send -async $Worker::worker $script
    }
    
    proc getSearchPattern {} {
        if {[string length $::pattern] == 0} {
            set ::pattern "*"
            return
        }
        switch -- $::type {
            1 { set ::pattern "*$::pattern*"}
            2 {set ::pattern "$::pattern*"}
            3 {set ::pattern "*$::pattern"}
            default {set ::pattern "*"}
        }
    }
    
    proc resetTreeview {} {
        .c.tv delete [.c.tv children {}]
    }
}

