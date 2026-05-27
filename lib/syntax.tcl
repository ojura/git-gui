# Source-level syntax highlighting for the diff viewer.
#
# A persistent helper process (lib/git-gui-highlight.py) keeps a lexer library
# warm and returns token spans, which we paint onto the diff text widget as Tk
# tags only. We never insert, delete, or rewrite a character of the diff buffer,
# so per-line / per-hunk staging (which reconstructs patches from the buffer
# text) is unaffected.
#
# Two user-facing knobs, both git config:
#   gui.diffsyntax     true|false  - master switch
#   gui.diffsyntaxmode tint|context
#       tint    - added/removed lines get a light background and syntax owns the
#                 foreground on every line (modern diff-tool look)
#       context - classic solid green/red on changed lines; syntax colour only
#                 on unchanged context lines

# Set up tags, cache config, and start the helper. Called once after the diff
# widget and its d_+/d_- tags exist.
proc syntax_setup {} {
	global ui_diff repo_config
	global syntax_fd syntax_reqid syntax_enabled syntax_mode
	global syntax_gen syntax_rx_state syntax_tint

	set syntax_fd {}
	set syntax_reqid 0
	set syntax_gen 0
	set syntax_rx_state header
	array unset ::syntax_pending
	set syntax_enabled [expr {$repo_config(gui.diffsyntax) eq {true}}]
	set syntax_mode $repo_config(gui.diffsyntaxmode)
	# Boolean mirror of the mode for the context-menu checkbutton.
	set syntax_tint [expr {$syntax_mode eq {tint}}]

	# Dark foregrounds, legible on white and on the light +/- tints.
	$ui_diff tag configure synkw  -foreground {#0033b3}
	$ui_diff tag configure syntyp -foreground {#008080}
	$ui_diff tag configure synstr -foreground {#a31515}
	$ui_diff tag configure syncom -foreground {#3f7e3f}
	$ui_diff tag configure synnum -foreground {#9b4f0f}
	$ui_diff tag configure synfn  -foreground {#795e26}
	$ui_diff tag configure synpre -foreground {#a626a4}

	# Syntax foreground must win over d_+/d_- on changed lines, but the
	# selection highlight must still win over syntax.
	foreach t {synkw syntyp synstr syncom synnum synfn synpre} {
		$ui_diff tag raise $t
	}
	$ui_diff tag raise sel

	syntax_apply_mode
	if {$syntax_enabled} syntax_start
}

# Configure the d_+/d_- tags for the current colour mode.
proc syntax_apply_mode {} {
	global ui_diff syntax_enabled syntax_mode
	if {$syntax_enabled && $syntax_mode eq {tint}} {
		$ui_diff tag configure d_+ -foreground {} -background {#e6ffe6}
		$ui_diff tag configure d_- -foreground {} -background {#ffe6e6}
	} else {
		$ui_diff tag configure d_+ -foreground {#00a000} -background {}
		$ui_diff tag configure d_- -foreground red -background {}
	}
}

# Remove all syntax tags from the buffer (leaving the diff +/- tags alone).
proc syntax_clear_tags {} {
	global ui_diff
	foreach t {synkw syntyp synstr syncom synnum synfn synpre} {
		$ui_diff tag remove $t 1.0 end
	}
}

# Context-menu handler. The checkbuttons have already written ::syntax_enabled
# and ::syntax_tint; reconcile the mode, repaint the current diff, and start the
# helper on demand. Bumping the generation drops any in-flight stale response.
proc syntax_toggle {} {
	global syntax_enabled syntax_mode syntax_tint syntax_fd syntax_gen
	set syntax_mode [expr {$syntax_tint ? {tint} : {context}}]
	incr syntax_gen
	syntax_clear_tags
	syntax_apply_mode
	if {$syntax_enabled && $syntax_fd eq {}} syntax_start
	syntax_highlight_diff
}

# (Re)spawn the helper. Any failure (no python3, no Pygments) silently leaves
# syntax_fd empty, which disables highlighting without disturbing the diff.
proc syntax_start {} {
	global syntax_fd oguilib
	if {$syntax_fd ne {}} return
	set helper [file join $oguilib git-gui-highlight.py]
	if {[catch {set fd [open "|[list python3 $helper]" r+]}]} {
		set syntax_fd {}
		return
	}
	fconfigure $fd -encoding utf-8 -blocking 0 -buffering full
	set syntax_fd $fd
	fileevent $fd readable syntax_on_readable
}

# Send one batch as a non-blocking request; the response is handled later by
# syntax_on_readable. Drops the helper on write failure (degrade to no colour).
proc syntax_send {rid path texts} {
	global syntax_fd
	if {[catch {
		puts $syntax_fd "REQ $rid [llength $texts] $path"
		foreach t $texts {puts $syntax_fd $t}
		flush $syntax_fd
	}]} syntax_close
}

proc syntax_close {} {
	global syntax_fd
	catch {close $syntax_fd}
	set syntax_fd {}
}

# Readable handler: parse RES headers and span lines as they arrive. fileevent
# can deliver partial output, so the parse state persists across invocations.
proc syntax_on_readable {} {
	global syntax_fd syntax_rx_state syntax_rx_rid syntax_rx_left syntax_rx_spans
	if {$syntax_fd eq {}} return
	while {1} {
		if {[gets $syntax_fd line] < 0} {
			if {[eof $syntax_fd]} syntax_close
			return
		}
		if {$syntax_rx_state eq {header}} {
			if {[lindex $line 0] eq {RES}} {
				set syntax_rx_rid  [lindex $line 1]
				set syntax_rx_left [lindex $line 2]
				set syntax_rx_spans {}
				if {$syntax_rx_left > 0} {
					set syntax_rx_state spans
				} else {
					syntax_apply_spans $syntax_rx_rid {}
				}
			}
		} else {
			lappend syntax_rx_spans $line
			if {[incr syntax_rx_left -1] <= 0} {
				syntax_apply_spans $syntax_rx_rid $syntax_rx_spans
				set syntax_rx_state header
			}
		}
	}
}

# Paint a completed response, unless the diff it was computed for has since been
# replaced (generation mismatch, bumped in clear_diff) or is otherwise unknown.
proc syntax_apply_spans {rid spans} {
	global ui_diff syntax_pending syntax_gen syntax_mode
	if {![info exists syntax_pending($rid)]} return
	lassign $syntax_pending($rid) gen linemap off
	unset syntax_pending($rid)
	if {$gen != $syntax_gen} return
	foreach span $spans {
		lassign $span idx col len cls
		set entry [lindex $linemap $idx]
		if {$entry eq {}} continue
		lassign $entry l cat
		# Context mode colours only unchanged lines.
		if {$syntax_mode eq {context} && $cat ne {context}} continue
		set a "$l.0 + [expr {$off + $col}] chars"
		set b "$l.0 + [expr {$off + $col + $len}] chars"
		catch {$ui_diff tag add syn$cls $a $b}
	}
}

# Post-load pass over the freshly rendered diff: collect code lines, ask the
# helper for token spans, and tag them. Handles plain 2-way diffs; 3-way,
# conflict, and submodule diffs are left untouched for now.
proc syntax_highlight_diff {} {
	global ui_diff syntax_fd syntax_enabled syntax_mode current_diff_path
	global syntax_reqid syntax_pending syntax_gen is_3way_diff

	if {!$syntax_enabled || $syntax_fd eq {} || $current_diff_path eq {}} return

	# Reconstruct the post-image (context + added) and pre-image (context +
	# removed) in file order, so the helper can lex each as one document and
	# keep state across lines (block comments, multi-line strings). Each image
	# maps back to its diff-buffer lines via a parallel {line category} list.
	# Combined (3-way merge / conflict) diffs carry a 2-column marker; plain
	# 2-way diffs one. The added/removed classification spans both forms.
	set off [expr {$is_3way_diff ? 2 : 1}]
	set last [lindex [split [$ui_diff index end] .] 0]
	set new_map {}; set new_txt {}
	set old_map {}; set old_txt {}
	for {set l 1} {$l < $last} {incr l} {
		set cat [syntax_line_category [$ui_diff tag names $l.0]]
		if {$cat eq {skip}} continue
		if {$cat eq {}} {
			# Untagged: a code context line has only spaces in the marker
			# columns; anything else (diff-header leftovers) is not code.
			if {[string trim [$ui_diff get $l.0 "$l.0 + $off chars"]] ne {}} continue
			set cat context
		}
		set code [$ui_diff get "$l.0 + $off chars" "$l.0 lineend"]
		if {$cat ne {removed}} {
			lappend new_map [list $l $cat]
			lappend new_txt $code
		}
		if {$cat ne {added}} {
			lappend old_map [list $l $cat]
			lappend old_txt $code
		}
	}

	# The post-image carries every context line, so it suffices for context
	# mode; tint mode also needs the pre-image to colour removed lines.
	syntax_send_image $new_txt $new_map $off
	if {$syntax_mode eq {tint}} {
		syntax_send_image $old_txt $old_map $off
	}
}

# Classify a diff line from its tags: added | removed | context | skip, or {}
# when untagged (the caller decides context-vs-not from the marker columns).
# Handles plain 2-way tags (d_+, d_-) and combined 3-way tags (d_s+/d_+s/d_++
# and d_s-/d_-s/d_--). Hunk headers, conflict markers, and submodule/info lines
# are skipped (not source code).
proc syntax_line_category {tags} {
	if {[lsearch -exact $tags d_@] >= 0} {return skip}
	foreach t {d_+ d_s+ d_+s d_++} {
		if {[lsearch -exact $tags $t] >= 0} {return added}
	}
	foreach t {d_- d_s- d_-s d_--} {
		if {[lsearch -exact $tags $t] >= 0} {return removed}
	}
	foreach t {d< d| d= d> d_info d_rescan} {
		if {[lsearch -exact $tags $t] >= 0} {return skip}
	}
	return {}
}

# Queue one image (its line texts, the parallel {line category} map, and the
# marker-column width) for highlighting. Records the mapping under a fresh
# request id at the current buffer generation; syntax_apply_spans paints the
# response when it arrives.
proc syntax_send_image {texts linemap off} {
	global current_diff_path syntax_reqid syntax_pending syntax_gen
	if {$texts eq {}} return
	incr syntax_reqid
	set syntax_pending($syntax_reqid) [list $syntax_gen $linemap $off]
	syntax_send $syntax_reqid $current_diff_path $texts
}
