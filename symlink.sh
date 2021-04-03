#!/bin/bash

##  +-----------------------------------+-----------------------------------+
##  |                                                                       |
##  | Copyright (c) 2016-2020, Andres Gongora <mail@andresgongora.com>.     |
##  |                                                                       |
##  | This program is free software: you can redistribute it and/or modify  |
##  | it under the terms of the GNU General Public License as published by  |
##  | the Free Software Foundation, either version 3 of the License, or     |
##  | (at your option) any later version.                                   |
##  |                                                                       |
##  | This program is distributed in the hope that it will be useful,       |
##  | but WITHOUT ANY WARRANTY; without even the implied warranty of        |
##  | MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         |
##  | GNU General Public License for more details.                          |
##  |                                                                       |
##  | You should have received a copy of the GNU General Public License     |
##  | along with this program. If not, see <http://www.gnu.org/licenses/>.  |
##  |                                                                       |
##  +-----------------------------------------------------------------------+



##
##
##	DESCRIPTION:
##	Run this script to symlink all your config files under "dotfiles".
##
##	`symlink.sh` will traverse `./config` and all subdirectories in search
##	for any config file whose name matches `$USER@$HOME.config`. Any valid
##	config file will be parsed line by line. Each line must contain two
##	paths. The first path is where you want to link your file to
##	(i.e. where your system expects to find a given file, like for example
##	`~/.bashrc`). The second path is relative to this folder's `./dotfiles/`
##	and indicates the "original" file you want to link. Both paths must be
##	spearated by spaces or tabs. If you want to add spaces _within_ any of
##	the path, you must escape them with `\`
##	(e.g. `/home/user/folder\ with\ many\ spaces/`).
##
##	Your symlink-config files may also have include statements to other
##	config files that may no longer match `$USER@$HOME.config`. This is
##	useful if you want to share the configuration among several machines.
##	To include a config file, just add a line that starts with `include`
##	followed by the relative path (under `./config/`) to the configuration
##	file. For example, you can have `.config/bob@pc.config` and
##	`.config/bob@laptopt.config` both containing a  single line
##	`include shared/home.config`, and then a file
##	`.config/shared/home.config` with your actual symlink configuration.
##
##



symlink()
{
	########################################################################
	## @brief Process either a config file or traverse a config directory
	##
	## @param config file or directory
	##
	########################################################################
	parseConfig()
	{
		local config=$1

		if [ -z $config ]; then
			printError "No config target specified"
			exit 1
		elif [ -d $config ]; then
			parseConfigDir $config
		else # is file
			parseConfigFile $config
		fi
	}






	########################################################################
	## @brief Traverse directory resursively in search for any configuration
	##        file whose name matches "${USER}@${HOSTNAME}.config".
	##
	## @param dir to parse
	##
	########################################################################
	parseConfigDir()
	{
		local dir=$1
		[ $VERBOSE == true ] && printInfo "Parsing directory $dir"


		for file in "$dir"/*; do
			[ -e "$file" ] || continue

			## IF FILE
			## - Check if it matches ${USER}@${HOSTNAME} -> Parse
			if [ -f "$file" ]; then
				local file_name=$(basename "$file" | sed 's/\*/\.\+/g')
				if [[ "${USER}@${HOSTNAME}.config" =~ $file_name ]]; then
					[ $verbose ] && printSuccess "Valid configuration file for ${USER}@${HOSTNAME} found: $file"
					parseConfigFile "$file"
				fi

			## IF DIR
			elif [ -d "$file" ]; then
				parseConfigDir "$file"
			fi
		done
	}






	########################################################################
	## @brief Parse configuration file to extract link instruction and
	##        recursive file inclusions.
	##
	## Parses configuration file. For each line, if it contains a pair
	## of paths, it creates a simlink from the first to the second. If
	## the line starts with an "include" statement followed by a path
	## to another configuration file, said file is parsed as well.
	##
	## The path of the configuration files to be included and
	## any src file (original to create link to) are relative to
	## to dotfiles/config/ and dotfiles/doftfiles respectively.
	##
	## To ensure orderly processing, all includes and links are first
	## added to separate arrays. At the end of this function, these
	## arrays are processed (links before includes).
	##
	## @param configuration file to parse
	##
	########################################################################
	parseConfigFile()
	{
		local config_file=$1
		local srcs=()
		local dsts=()
		local include_configs=()


		printInfo "Parsing configuartion-file $config_file"


		## READ LINE BY LINE
		## -r do not interpret escape characters
		while read -r line; do

			## REMOVE COMMENTS, DOUBLE SPACES, AND SKIP EMPTY LINES
			local line=$(echo "$line" | sed 's/#.*$//g; s/\s\s*/ /g')
			[ -z "$line" ] && continue


			## SEPARATE LINES
			## - To avoid issues with escaped whitespaces, replace them with '\a'
			## - Separate words
			## - Restore escaped whitespaces
			local line=$(echo "$line" | sed 's/\\\ /\a/g')
			local word_count=$(echo "$line" | wc -w)
			local word_1=$(echo "$line" | cut -d " " -f 1 | sed 's/\a/ /g')
			local word_2=$(echo "$line" | cut -d " " -f 2 | sed 's/\a/ /g')


			## PROCESS LINE
			## - Check if include -> Save in array for later
			## - Symlink
			## - Warn if could not process
			if [ $word_count -eq 2 ] && [ "$word_1" = "include" ]; then
				new_include_config="$(dirname ${config_file})/$word_2"
				if [ -f "$new_include_config" ]; then
					[ $VERBOSE == true ] && printInfo "Found include statement $line"
					include_configs=("${include_configs[@]}" "$new_include_config")
				else
					printError "Could not include file: $include_file"
				fi

			elif [ $word_count -eq 2 ]; then
				[ $VERBOSE == true ] && printInfo "Found link statement $line"
				local dst="${word_1/'~'/$HOME}"
				local src="$DOTFILES_ROOT/dotfiles/$word_2"
				dsts=("${dsts[@]}" "$dst")
				srcs=("${srcs[@]}" "$src")

			else
				printWarn "Can not parse line in $config_file: $line"
			fi


		done < "$config_file"


		## PROCESS LINK LIST
		if [ $LIST_FILES_ONLY == true ]; then
			## STORE LISTS
			[ $VERBOSE == true ] && printInfo "Storing link list for $config_file"
			echo $config_file >> $DOTFILES_CFG_LIST_FILE

			for i in ${!dsts[@]}; do
				local src=${srcs[$i]}
				local dst=${dsts[$i]}
				echo $src >> $DOTFILES_SRC_LIST_FILE
				echo $dst >> $DOTFILES_DST_LIST_FILE
			done


		else
			## CREATE LINKS
			[ $verbose == true ] && printInfo "Create links..."
			for i in "${!dsts[@]}"; do
				local src="${srcs[$i]}"
				local dst="${dsts[$i]}"
				link "$src" "$dst"
			done
		fi


		## PARSE ALL INCLUDES STORED IN ARRAY
		[ $VERBOSE == true ] && printInfo "Parsing cofiguration files included by $config_file"
		for include_config in "${include_configs[@]}"; do
			echo ""
			parseConfigFile $include_config
		done
	}







	########################################################################
	## @brief create symlink between source and destiny.
	##
	## This function creates a symlink from dst to src. However,
	## before linking, it creates the full path to src and
	## then checks if the file already exists. If the file is already
	## a link (i.e. you have run this script before) it continues
	## as normal. If not, it will ask the user what to do.
	##
	## @param src file/dir (original)
	## @param dst file/dir (symlink to create)
	##
	########################################################################
	link()
	{
		local src=$1 dst=$2
		local dst=$(echo "${dst/\~/$HOME}" )
		[ $VERBOSE == true ] && printInfo "Trying to link $dst -> $src"


		## CHECK THAT SOURCE FILE EXISTS
		if [ ! -e "$src" ]; then
			printError "Failed linking $dst because $src does not exist"
			return
		fi


		## CREATE PARENT DIRECTORIES IF NEEDED
		dst_parent_dir=$(dirname "$dst")
		if [ ! -d "$dst_parent_dir" ]; then
			printInfo "Creating new directory to link dotfiles into: $dst_parent_dir"
			mkdir -p "$dst_parent_dir"
		fi


		## DECIDE ACTION TO EXECUTE (by default link, "l")
		## * If dst exists
		##   * If dst already points to src, do nothing, "a"
		##   * If same file (loopback), skip, "s"
		##   * If dst is a different file/dir
		##     * If global action not specified -> Ask user
		##     * If global action defined -> Retrieve gloabl action
		##
		local action="l"
		if [ -e "$dst" -o  -f "$dst" -o -d "$dst" -o -L "$dst" ]; then

			## CHECK IF ALREADY SYMLINKED
			## readlink: print symbolic link or canonical file name
			##
			local dst_link=$(readlink "$dst")
			if [ -e "$dst" -a "$dst_link" == "$src" ]; then
				local action="a"

			## CHECK IF SAME FILE
			elif [ "$dst" == "$src" ]; then
				printError "Trying to link to tiself $dst -> $src"
				local action="s"

			## IF NOT SYMLINKED, ASK USER WHAT TO DO
			elif [ -z "$GLOBAL_ACTION" ]; then

				local action=$(promptUser \
				               "File already exists: $dst ($(basename "$src"))" \
				               "[s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all?" "sSoObB" "")

				case "$action" in
					S|O|B )		GLOBAL_ACTION="$action" ;;
					s|o|b )		;;
					*)		printError "Invalid option"; exit 1
				esac

			## UPDATE ACTION WITH GLOBAL IF DEFINED
			else
				local action="${GLOBAL_ACTION:-$action}"

			fi
		fi


		## EXECUTE ACTION & LINK
		## * Handle action
		##   * Handle conflicting file, if any
		##   * Infor user
		##   * Return early if no symlink needed
		## * Create symlink
		##
		case "$action" in
			a)		printSuccess "Already linked $dst"
					return;;

			s|S)    printInfo "Skipped $src"
					return ;;

			b|B )   mv "$dst" "${dst}.backup"
					printInfo "Moved $dst to ${dst}.backup" ;;

			o|O )   rm -rf "$dst"
					printWarn "Removed original $dst" ;;

			l)		;; #link

			*)		printError "Invalid option '$action'"; exit 1
		esac
		ln -s "$src" "$dst" && printSuccess "$dst -> $src"
	}






	########################################################################
	## @brief Helper function to copy dotfiles to a different place other
	##        that the current, local folder.
	##
	########################################################################
	syncDotfiles()
	{
		local target=$1
		if [ -z "$target" ]; then
			printError "No sync (i.e. copy) target specified for $SYNC_METHOD"
			exit 1
		fi
		if [ -z "$SYNC_METHOD" ]; then
			printError "No sync method to copy dotfiles. Currently supported:"
			printText "--rsync: unidirectional, remote files will be overwritten"
			printText "--unison: bidirectional, synchronizes local and remote copy"
		fi


		## INCLUDE ALL FILES LISTED BY `parseConfig`
		## Edit file/dir paths to convert into filters
		local include_filter_file="${TMP_FILE_ROOT}_include.filter"
		echo "" > $include_filter_file
		cat $DOTFILES_CFG_LIST_FILE >> $include_filter_file
		cat $DOTFILES_SRC_LIST_FILE >> $include_filter_file
		sed -i '/^$/d;s/$//;s/\.\///' $include_filter_file
		sed -i "s:$DOTFILES_ROOT/::" $include_filter_file
		[ $VERBOSE == true ] \
			&& printInfo "Local files to be copied:" \
			&& echo "" \
			&& cat $include_filter_file


		syncWithRsync()
		{
			sed -i 's/$/**/' $include_filter_file

			[ $VERBOSE == true ] && echo ""
			rsync \
				-rlptDhP \
				--prune-empty-dirs \
				--exclude=".git**" \
				--include="*/" \
				--include="symlink.sh" \
				--include="bash-tools/**" \
				--include-from=$include_filter_file \
				--exclude="*" \
				"$local_dotfiles_dir/" \
				"$target"
			local return=$?
			[ $VERBOSE == true ] && echo ""
			[ $return != 0 ] && printError "rsync failed" && return 1 \
			||printSuccess "rsync successful" && return 0
		}


		syncWithUnison()
		{
			local unison_profile="dotfiles_unison_config.prf"
			local unison_dir="$HOME/.unison"
			local unison_config_file="$unison_dir/$unison_profile"
			local local_path=$local_dotfiles_dir


			## CREATE UNISON RULES
			mkdir -p $unison_dir && echo "" > $unison_config_file
			echo "# Roots of the synchronization" >> $unison_config_file
			echo "root = $local_path" >> $unison_config_file
			echo "root = $target" >> $unison_config_file

			echo "" >> $unison_config_file
			echo "# Config" >> $unison_config_file
			echo "times = true" >> $unison_config_file
			echo "auto = true" >> $unison_config_file
			echo "owner = false" >> $unison_config_file
			echo "prefer = newer" >> $unison_config_file
			echo "batch = true" >> $unison_config_file
			[ $VERBOSE == false  ] && echo "silent = true" >> $unison_config_file

			echo "" >> $unison_config_file
			echo "# Sync" >> $unison_config_file
			echo "path = bash-tools" >> $unison_config_file
			echo "path = symlink.sh" >> $unison_config_file
			while read line; do
				echo "path = $line" >> $unison_config_file
			done <$include_filter_file


			[ $VERBOSE == true ] && \
				printInfo "Unison config:" \
				&& echo "" \
				&& cat $unison_config_file \
				&& echo ""


			[ $VERBOSE == true ] && echo ""
			unison $unison_profile
			local return=$?
			[ $VERBOSE == true ] && echo ""
			rm $unison_config_file
			[ $return != 0 ] && printError "Unison failed" && return 1 \
			||printSuccess "Unison successful" && return 0
		}


		case "$SYNC_METHOD" in

			"rsync")
				printInfo "rsync local -> $target"
				syncWithRsync || exit 1
				;;

			"unison")
				printInfo "unison local -> $target"
				syncWithUnison || exit 1
				;;

			*)
				printError "Sync method '$SYNC_METHOD' not supported"; exit 1
		esac
		rm $include_filter_file
	}







	########################################################################
	## @brief Copy dotfiles and create symlinks on remote machine.
	##
	## Copies with rsync/unison all your files to the specified target and
	## symlinks the configuartion in place. This function relies heavily
	## on `rsync`'s include and exclude rules.
	##
	## @param target "username@host" to connect to
	##
	########################################################################
	sshSymlink()
	{
		local host=$1


		## SYNC DOTFILES
		case "$SYNC_METHOD" in
			"rsync")
				local target="$host:~/$REMOTE_DOTFILES_DIR"
				;;

			"unison")
				local target="ssh://$host/$REMOTE_DOTFILES_DIR"
				;;

			*)
				printError "Sync method '$SYNC_METHOD' not supported in conjunction with SSH"; exit 1
		esac
		syncDotfiles "$target"


		## SYMLINK OVER SSH
		printInfo "Running symlink script remotely..."
		ssh "$host" "~/$REMOTE_DOTFILES_DIR/symlink.sh --backup" \
		&& printSuccess "SSH connection successful" \
		|| printError "Failed to connect over SSH"
	}






	########################################################################
	## MAIN
	########################################################################
	local DOTFILES_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
	[ -L "$DOTFILES_ROOT" ] &&  local DOTFILES_ROOT=$(readlink "$DOTFILES_ROOT")
	source "$DOTFILES_ROOT/bash-tools/bash-tools/user_io.sh"

	local random=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
	TMP_FILE_ROOT="/tmp/andresgongora_dotfiles"
	DOTFILES_CFG_LIST_FILE="${TMP_FILE_ROOT}_cfgs_${random}.txt"
	DOTFILES_SRC_LIST_FILE="${TMP_FILE_ROOT}_srcs_${random}.txt"
	DOTFILES_DST_LIST_FILE="${TMP_FILE_ROOT}_dsts_${random}.txt"

	echo "" > $DOTFILES_CFG_LIST_FILE
	echo "" > $DOTFILES_SRC_LIST_FILE
	echo "" > $DOTFILES_DST_LIST_FILE


	## RUNTIME VARIABLES
	local verbose=false
	local run_cmd="parseConfigDir"
	local symlink_mode=""
	local sync_method=""
	local sync_target=""
	local global_action=""
	local sudo_user=""
	local config="$DOTFILES_ROOT/config"
	local target_dir=".dotfiles"


	## PROCESS ARGUMENTS
	while (( "$#" )); do
		local cmd="$1"
		shift
		case "$cmd" in
			"--ssh")
				if [ -z "$symlink_mode" ]; then
					local symlink_mode="ssh"
					local sync_target=$1
					shift
				else
					printError "Symlink method already set, can not use --ssh as well"
					exit 1
				fi
				;;

			"--unison")
				if [ -z "$sync_method" ]; then
					local sync_method="unison"
				else
					printError "SSH sync methond already set, can not use --unison as well"
					exit 1
				fi
				;;

			"--rsync")
				if [ -z "$sync_method" ]; then
					local sync_method="rsync"
				else
					printError "SSH sync methond already set, can not use --rsync as well"
					exit 1
				fi
				;;

			"--target")
				local target_dir=$1
				shift
				;;


			"-v"|"--verbose")
				local verbose=true
				;;

			"-B"|"--backup")
				if [ -z "$global_action" ]; then
					local global_action="B"
				else
					printError "Global action already set, can not use --backup as well"
					exit 1
				fi
				;;

			"-O"|"--overwrite")
				if [ -z "$global_action" ]; then
					local global_action="O"
				else
					printError "Global action already set, can not use --overwrite as well"
					exit 1
				fi
				;;

			"-c"|"--config")
				local config=$1
				shift
				;;

			*)
				printError "Invalid argument '$cmd'"; exit 1
		esac
	done


	## APPLY ARGUMENTS
	LIST_FILES_ONLY=false
	GLOBAL_ACTION=$global_action
	VERBOSE=$verbose
	REMOTE_DOTFILES_DIR="$target_dir"
	SYNC_METHOD=$sync_method

	if [ -z "$symlink_mode" ]; then
		local symlink_mode="local"
	fi


	## RUN
	if [ $symlink_mode == "ssh" ]; then
		printHeader "Linking your dotfiles over SSH..."
		LIST_FILES_ONLY=true
		parseConfig $config
		sshSymlink $sync_target

	elif [ $symlink_mode == "local" ]; then
		printHeader "Linking your dotfiles files..."
		[ $VERBOSE == true ] && printInfo "Parsing $config"
		parseConfig $config

		## CREATE `~/.dotfiles`
		## If linking was successful, and your dotfiles folder is not stored
		## under `~/.dotfiles`, create a symlink at said location .
		local dotfiles_symlink="$HOME/$REMOTE_DOTFILES_DIR"
		if [ ! -d "$dotfiles_symlink" ]; then
			link "$DOTFILES_ROOT" "$dotfiles_symlink"
		fi

	else
		printError "Unsoported symlink mode $symlink_mode"
		exit 1
	fi


	rm $DOTFILES_CFG_LIST_FILE
	rm $DOTFILES_SRC_LIST_FILE
	rm $DOTFILES_DST_LIST_FILE
}

(symlink $@)
