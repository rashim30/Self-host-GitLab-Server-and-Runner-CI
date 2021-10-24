#!/bin/bash

#./mirror_github_to_gitlab.sh "a-t-0" "testrepo" "filler_github"

source src/helper.sh
source src/hardcoded_variables.txt
source src/creds.txt
source src/get_gitlab_server_runner_token.sh
source src/push_repo_to_gitlab.sh

# Hardcoded data:
echo "MIRROR_LOCATION=$MIRROR_LOCATION"
# Get GitHub username.
github_username=$1
echo "github_username=$github_username"
# Get GitHub repository name.
github_repo=$2
echo "github_repo=$github_repo"
# OPTIONAL: get GitHub personal access token or verify ssh access to support private repositories.
github_personal_access_code=$3
echo "github_personal_access_code=$github_personal_access_code"
# Get GitLab username.
gitlab_username=$(echo $gitlab_server_account | tr -d '\r')
echo "gitlab_username=$gitlab_username"
# Get GitLab user password.
gitlab_server_password=$(echo $gitlab_server_password | tr -d '\r')
echo "gitlab_server_password=$gitlab_server_password"
# Specify GitLab mirror repository name.
gitlab_repo="$github_repo"
echo "gitlab_repo=$gitlab_repo"



# Ensure mirrors directory is created.
$(create_dir "$MIRROR_LOCATION")
$(create_dir "$MIRROR_LOCATION/GitHub")
$(create_dir "$MIRROR_LOCATION/GitLab")
#assert_equal "$(dir_exists "$MIRROR_LOCATION")" "FOUND" 

# Activates/enables the ssh for 
activate_ssh_account() {
	git_username=$1
	eval "$(ssh-agent -s)"
	ssh-add ~/.ssh/"$git_username"
}

# Check ssh-access to GitHub repo.
check_ssh_access_to_repo() {
	github_username=$1
	github_repository=$2
	retry=$3
	
	my_service_status=$(git ls-remote git@github.com:$github_username/$github_repository.git 2>&1)
	found_error_in_ssh_command=$(lines_contain_string "ERROR" "\${my_service_status}")
	
	if [ "$found_error_in_ssh_command" == "NOTFOUND" ]; then
		echo "HASACCESS"
	elif [ "$found_error_in_ssh_command" == "FOUND" ]; then
		if [ "$retry" == "YES" ]; then
			echo "NOACCESS"
			# TODO: Throw error
			#(A public repository should grant ssh access even if no ssh credentials for that GitHub user is given.)
		else
			activate_ssh_account "$github_username"
			check_ssh_access_to_repo "$github_username" "$github_repository" "YES"
		fi
	fi
}

has_access=$(check_ssh_access_to_repo "$github_username" "$github_repo")
echo "has_access$has_access"

# check if repo is private
# skip

verify_github_repository_is_cloned() {
	github_repository=$1
	target_directory=$2
	found_repo=$(dir_exists "$target_directory")
	if [ "$found_repo" == "NOTFOUND" ]; then
		read -p "The following GitHub repository: $github_repository \n was not cloned correctly into the path:$MIRROR_LOCATION/GitHub/$github_repository"
		exit 125
	fi
}

# Clone GitHub repository to folder src/mirror/GITHUB
clone_github_repository "$github_username" "$github_repo" "$has_access" "$MIRROR_LOCATION/GitHub/$github_repo"
verify_github_repository_is_cloned "$github_repo" "$MIRROR_LOCATION/GitHub/$github_repository"


get_github_branches() {
    local -n arr=$1             # use nameref for indirection
	company=$2
	git_repository=$3
	arr=() # innitialise array with branches
	
	# Parse branches from branch list response
	while IFS= read -r line; do
		
		# Only parse remote branches.
		if [ "${line:0:17}" == "  remotes/origin/" ]; then
			
			# Remove the substring that identifies a remote branch to get the actual branch name up to the first space.
			# Assumes branch names can't contain spaces
			branch=$(get_rhs_of_line_till_character "${line:17}" " ")
			
			# Filter out the HEAD branch duplicate, by filtering on a substring that indicates the duplicate.
			if [ "${branch:0:10}" != "-> origin/" ]; then
				
				# Filter out git output artifacts of that do not start with a letter or number.
				# Assumes branch names always start with a letter or number.
				if grep '^[-0-9a-zA-Z]*$' <<<"${branch:0:1}" ;then 
					
					# Append the branch name to the array of branches
					echo "branch=$branch"
					arr+=("$branch")
				fi			
			fi
		fi
	# List branches and feed them into a line by line parser
	done <<< $(cd "$MIRROR_LOCATION/$company/$git_repository" && git branch --all)
}


# Make a list of the branches in the GitHub repository
get_github_branches github_branches "GitHub" "$github_repo"      # call function to populate the array
declare -p github_branches


# Check if the mirror repository exists in GitLab (Skipped)
# If the GItHub branch already exists in the GItLab mirror repository does not yet exist, create it.
create_repository "$gitlab_repo"


# Clone the GitLab repository from the GitLab server into the mirror directory
clone_repository "$github_repo" "$gitlab_username" "$personal_access_token" "$GITLAB_SERVER" "$MIRROR_LOCATION/GitLab/"

# Get a list of GitLab repository branches
get_github_branches gitlab_branches "GitLab" "$github_repo"      # call function to populate the array
declare -p gitlab_branches

# Get list of missing branches in GitLab
missing_branches_in_gitlab=(`echo ${github_branches[@]} ${gitlab_branches[@]} | tr ' ' '\n' | sort | uniq -u `)
echo "missing_branches_in_gitlab=$missing_branches_in_gitlab"


create_new_branch() {
	branch_name=$1
	company=$2
	git_repository=$3
	
	# create_repo branch
	output=$(cd "$MIRROR_LOCATION/$company/$git_repository" && git checkout -b $branch_name)
	
	# TODO: assert the branch is created
	
	# echo output
	echo "$output"
}

checkout_branch() {
	branch_name=$1
	company=$2
	git_repository=$3
	
	# create_repo branch
	output=$(cd "$MIRROR_LOCATION/$company/$git_repository" && git checkout $branch_name)
	
	# TODO: assert the branch is created
	
	# echo output
	echo "$output"
}

copy_files_from_github_to_gitlab_repo_branches() {
	git_repository=$1
	rsync -av --progress "$MIRROR_LOCATION/GitHub/$git_repository/" "$MIRROR_LOCATION/GitLab/$git_repository" --exclude .git
}

# Loop through the GitHub mirror repository branches and copy their content to GitLab if they are not yet in the GitLab repository.
for missing_branch_in_gitlab in ${missing_branches_in_gitlab[@]}; do
   
   # check if the branch is contained in GitHub branch array (to filter the difference containing a branch that is (still) in GitLab but not in GitHub)
   if [[ " ${github_branches[*]} " =~ " ${missing_branch_in_gitlab} " ]]; then
		# whatever you want to do when array contains value
		echo "missing_branch_in_gitlab=$missing_branch_in_gitlab"
		
		# Checkout that branch in GitHub
		checkout_branch "$missing_branch_in_gitlab" "GitHub" "$github_repo"
		
		# Check if the GitHub 	branch contains a .gitlab-ci.yml file.
		if test -f "$MIRROR_LOCATION/GitLab/$github_repo/.gitlab-ci.yml"; then
		
			# Create new branch in GitLab
			create_new_branch "$missing_branch_in_gitlab" "GitLab" "$github_repo"
			
			# Copy files from GitHub branch
			copy_files_from_github_to_gitlab_repo_branches "$github_repo"
			
			# Commit files to GitLab branch.
			commit_changes "$MIRROR_LOCATION/GitLab/$gitlab_repo"
			
			# Push committed files go GitLab.
			push_changes "$github_repo" "$gitlab_username" "$personal_access_token" "$GITLAB_SERVER" "$MIRROR_LOCATION/GitLab/"
			
			# Trigger CI build (is done automatically if it contains a .gitlab-ci.yml file)
			
			# Export build status to GitHub build-status-website repository
			src/./push_gitlab_build_status_to_github_website.sh "$github_username" "$github_repo" "$missing_branch_in_gitlab" "$has_access"
		fi
	fi
done

echo "DONE"

# If the GitHub branch does not yet exist in the GitLab mirror repository:
	# Create the branch in the local GitLab mirror repository.
	
# Checkout that branch in the local GitHub mirror repository.
# Get the latest GitHub mirror repository branch commit.
# Get the latest GitLab mirror repository branch commit.
# If the two commit sha's are not equal:
	# Delete the files in the GitLab mirror repository branch
	# Copy the files from the GitHub mirror repository into those of the GitLab repository.


#SKIP Check the commit in GitHub already exists in its GitLab mirror branch.
# SKIP If not, copy the files from the GitHub branch into the GitLab branch and push the commit with the same sha.
# TODO: write check to see if adding the files make a difference that can be committed.


############
# Run the GitLab CI on that commit of that branch.

# Wait until the Gitlab runner CI is finished for that commit.

# Once the GitLab runner CI is finished for that commit, push the build status to the build status website.