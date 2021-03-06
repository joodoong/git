#!/bin/sh

test_description='git p4 rename'

. ./lib-git-p4.sh

test_expect_success 'start p4d' '
	start_p4d
'

# We rely on this behavior to detect for p4 move availability.
test_expect_success 'p4 help unknown returns 1' '
	(
		cd "$cli" &&
		(
			p4 help client >errs 2>&1
			echo $? >retval
		)
		echo 0 >expected &&
		test_cmp expected retval &&
		rm retval &&
		(
			p4 help nosuchcommand >errs 2>&1
			echo $? >retval
		)
		echo 1 >expected &&
		test_cmp expected retval &&
		rm retval
	)
'

test_expect_success 'create files' '
	(
		cd "$cli" &&
		p4 client -o | sed "/LineEnd/s/:.*/:unix/" | p4 client -i &&
		cat >file1 <<-EOF &&
		A large block of text
		in file1 that will generate
		enough context so that rename
		and copy detection will find
		something interesting to do.
		EOF
		cat >file2 <<-EOF &&
		/*
		 * This blob looks a bit
		 * different.
		 */
		int main(int argc, char **argv)
		{
			char text[200];

			strcpy(text, "copy/rename this");
			printf("text is %s\n", text);
			return 0;
		}
		EOF
		p4 add file1 file2 &&
		p4 submit -d "add files"
	)
'

# Rename a file and confirm that rename is not detected in P4.
# Rename the new file again with detectRenames option enabled and confirm that
# this is detected in P4.
# Rename the new file again adding an extra line, configure a big threshold in
# detectRenames and confirm that rename is not detected in P4.
# Repeat, this time with a smaller threshold and confirm that the rename is
# detected in P4.
test_expect_success 'detect renames' '
	git p4 clone --dest="$git" //depot@all &&
	test_when_finished cleanup_git &&
	(
		cd "$git" &&
		git config git-p4.skipSubmitEdit true &&

		git mv file1 file4 &&
		git commit -a -m "Rename file1 to file4" &&
		git diff-tree -r -M HEAD &&
		git p4 submit &&
		p4 filelog //depot/file4 &&
		p4 filelog //depot/file4 | test_must_fail grep -q "branch from" &&

		git mv file4 file5 &&
		git commit -a -m "Rename file4 to file5" &&
		git diff-tree -r -M HEAD &&
		git config git-p4.detectRenames true &&
		git p4 submit &&
		p4 filelog //depot/file5 &&
		p4 filelog //depot/file5 | grep -q "branch from //depot/file4" &&

		git mv file5 file6 &&
		echo update >>file6 &&
		git add file6 &&
		git commit -a -m "Rename file5 to file6 with changes" &&
		git diff-tree -r -M HEAD &&
		level=$(git diff-tree -r -M HEAD | sed 1d | cut -f1 | cut -d" " -f5 | sed "s/R0*//") &&
		test -n "$level" && test "$level" -gt 0 && test "$level" -lt 98 &&
		git config git-p4.detectRenames $(($level + 2)) &&
		git p4 submit &&
		p4 filelog //depot/file6 &&
		p4 filelog //depot/file6 | test_must_fail grep -q "branch from" &&

		git mv file6 file7 &&
		echo update >>file7 &&
		git add file7 &&
		git commit -a -m "Rename file6 to file7 with changes" &&
		git diff-tree -r -M HEAD &&
		level=$(git diff-tree -r -M HEAD | sed 1d | cut -f1 | cut -d" " -f5 | sed "s/R0*//") &&
		test -n "$level" && test "$level" -gt 2 && test "$level" -lt 100 &&
		git config git-p4.detectRenames $(($level - 2)) &&
		git p4 submit &&
		p4 filelog //depot/file7 &&
		p4 filelog //depot/file7 | grep -q "branch from //depot/file6"
	)
'

# Copy a file and confirm that copy is not detected in P4.
# Copy a file with detectCopies option enabled and confirm that copy is not
# detected in P4.
# Modify and copy a file with detectCopies option enabled and confirm that copy
# is detected in P4.
# Copy a file with detectCopies and detectCopiesHarder options enabled and
# confirm that copy is detected in P4.
# Modify and copy a file, configure a bigger threshold in detectCopies and
# confirm that copy is not detected in P4.
# Modify and copy a file, configure a smaller threshold in detectCopies and
# confirm that copy is detected in P4.
test_expect_success 'detect copies' '
	git p4 clone --dest="$git" //depot@all &&
	test_when_finished cleanup_git &&
	(
		cd "$git" &&
		git config git-p4.skipSubmitEdit true &&

		cp file2 file8 &&
		git add file8 &&
		git commit -a -m "Copy file2 to file8" &&
		git diff-tree -r -C HEAD &&
		git p4 submit &&
		p4 filelog //depot/file8 &&
		p4 filelog //depot/file8 | test_must_fail grep -q "branch from" &&

		cp file2 file9 &&
		git add file9 &&
		git commit -a -m "Copy file2 to file9" &&
		git diff-tree -r -C HEAD &&
		git config git-p4.detectCopies true &&
		git p4 submit &&
		p4 filelog //depot/file9 &&
		p4 filelog //depot/file9 | test_must_fail grep -q "branch from" &&

		echo "file2" >>file2 &&
		cp file2 file10 &&
		git add file2 file10 &&
		git commit -a -m "Modify and copy file2 to file10" &&
		git diff-tree -r -C HEAD &&
		git p4 submit &&
		p4 filelog //depot/file10 &&
		p4 filelog //depot/file10 | grep -q "branch from //depot/file" &&

		cp file2 file11 &&
		git add file11 &&
		git commit -a -m "Copy file2 to file11" &&
		git diff-tree -r -C --find-copies-harder HEAD &&
		src=$(git diff-tree -r -C --find-copies-harder HEAD | sed 1d | cut -f2) &&
		test "$src" = file10 &&
		git config git-p4.detectCopiesHarder true &&
		git p4 submit &&
		p4 filelog //depot/file11 &&
		p4 filelog //depot/file11 | grep -q "branch from //depot/file" &&

		cp file2 file12 &&
		echo "some text" >>file12 &&
		git add file12 &&
		git commit -a -m "Copy file2 to file12 with changes" &&
		git diff-tree -r -C --find-copies-harder HEAD &&
		level=$(git diff-tree -r -C --find-copies-harder HEAD | sed 1d | cut -f1 | cut -d" " -f5 | sed "s/C0*//") &&
		test -n "$level" && test "$level" -gt 0 && test "$level" -lt 98 &&
		src=$(git diff-tree -r -C --find-copies-harder HEAD | sed 1d | cut -f2) &&
		test "$src" = file10 -o "$src" = file11 &&
		git config git-p4.detectCopies $(($level + 2)) &&
		git p4 submit &&
		p4 filelog //depot/file12 &&
		p4 filelog //depot/file12 | test_must_fail grep -q "branch from" &&

		cp file2 file13 &&
		echo "different text" >>file13 &&
		git add file13 &&
		git commit -a -m "Copy file2 to file13 with changes" &&
		git diff-tree -r -C --find-copies-harder HEAD &&
		level=$(git diff-tree -r -C --find-copies-harder HEAD | sed 1d | cut -f1 | cut -d" " -f5 | sed "s/C0*//") &&
		test -n "$level" && test "$level" -gt 2 && test "$level" -lt 100 &&
		src=$(git diff-tree -r -C --find-copies-harder HEAD | sed 1d | cut -f2) &&
		test "$src" = file10 -o "$src" = file11 -o "$src" = file12 &&
		git config git-p4.detectCopies $(($level - 2)) &&
		git p4 submit &&
		p4 filelog //depot/file13 &&
		p4 filelog //depot/file13 | grep -q "branch from //depot/file"
	)
'

test_expect_success 'kill p4d' '
	kill_p4d
'

test_done
