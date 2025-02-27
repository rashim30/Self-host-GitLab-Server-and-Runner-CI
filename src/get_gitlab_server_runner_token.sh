#!/bin/bash
# Source: https://github.com/MxNxPx/gitlab-cicd-demo/blob/aee86e45f5bc603a5055f0cd391cd6b184f1d6c3/get-runner-reg.sh
source src/hardcoded_variables.txt
#source src/creds.txt
source src/helper.sh

get_gitlab_server_runner_tokenV1() {
	GITURL="$GITLAB_SERVER_HTTP_URL"
	GITUSER="$gitlab_server_account"
	GITROOTPWD="$gitlab_server_password"
	#echo "GITUSER=$GITUSER"
	#echo "GITROOTPWD=$GITROOTPWD"
	
	# 1. curl for the login page to get a session cookie and the sources with the auth tokens
	body_header=$(curl -k -c "$LOG_LOCATION"gitlab-cookies.txt -i "${GITURL}/users/sign_in" -sS)
	#echo "body_header=$body_header"
	
	# grep the auth token for the user login for
	#   not sure whether another token on the page will work, too - there are 3 of them
	csrf_token=$(echo $body_header | perl -ne 'print "$1\n" if /new_user.*?authenticity_token"[[:blank:]]value="(.+?)"/' | sed -n 1p)
	#echo "csrf_token=$csrf_token"
	
	# 2. send login credentials with curl, using cookies and token from previous request
	curl -sS -k -b "$LOG_LOCATION"gitlab-cookies.txt -c "$LOG_LOCATION"gitlab-cookies.txt "${GITURL}/users/sign_in" \
		--data "user[login]=${GITUSER}&user[password]=${GITROOTPWD}" \
		--data-urlencode "authenticity_token=${csrf_token}"  -o /dev/null
	
	# 3. send curl GET request to gitlab runners page to get registration token
	body_header=$(curl -sS -k -H 'user-agent: curl' -b "$LOG_LOCATION"gitlab-cookies.txt "${GITURL}/admin/runners" -o "$LOG_LOCATION"gitlab-header.txt)
	
	if [ "$body_header" == "" ]; then
		get_registration_token_with_python
		reg_token=$(cat $RUNNER_REGISTRATION_TOKEN_FILEPATH)
	else
		reg_token=$(cat "$LOG_LOCATION"gitlab-header.txt | perl -ne 'print "$1\n" if /code id="registration_token">(.+?)</' | sed -n 1p)
		echo "$reg_token" > "$RUNNER_REGISTRATION_TOKEN_FILEPATH"
	fi
	if [ "$reg_token" == "" ]; then
		echo "ERROR, would have expected the runner registration token to be found by now, but it was not."
		exit 1
	fi
	#echo "$reg_token"
}


get_gitlab_server_runner_tokenV0() {
	export GITURL="$GITLAB_SERVER_HTTP_URL"
	export GITUSER="$gitlab_server_account"
	export GITROOTPWD="$gitlab_server_password"
	
	# 1. curl for the login page to get a session cookie and the sources with the auth tokens
	body_header=$(curl -k -c gitlab-cookies.txt -i "${GITURL}/users/sign_in" -sS)
	
	# grep the auth token for the user login for
	#   not sure whether another token on the page will work, too - there are 3 of them
	csrf_token=$(echo $body_header | perl -ne 'print "$1\n" if /new_user.*?authenticity_token"[[:blank:]]value="(.+?)"/' | sed -n 1p)
	
	# 2. send login credentials with curl, using cookies and token from previous request
	curl -sS -k -b gitlab-cookies.txt -c gitlab-cookies.txt "${GITURL}/users/sign_in" \
		--data "user[login]=${GITUSER}&user[password]=${GITROOTPWD}" \
		--data-urlencode "authenticity_token=${csrf_token}"  -o /dev/null
	
	# 3. send curl GET request to gitlab runners page to get registration token
	body_header=$(curl -sS -k -H 'user-agent: curl' -b gitlab-cookies.txt "${GITURL}/admin/runners" -o gitlab-header.txt)
	reg_token=$(cat gitlab-header.txt | perl -ne 'print "$1\n" if /code id="registration_token">(.+?)</' | sed -n 1p)
	echo $reg_token
	# TODO: restore the functionality of this method!
	#echo "sPgAnNea3WxvTRsZN5hB"
}

# source src/get_gitlab_server_runner_token.sh && get_registration_token_with_python
get_registration_token_with_python() {
	# delete the runner registration token file if it exist
	if [ -f "$RUNNER_REGISTRATION_TOKEN_FILEPATH" ] ; then
	    rm "$RUNNER_REGISTRATION_TOKEN_FILEPATH"
	fi
	
	# Check if the repository exists
	$(download_repository "a-t-0" "$REPONAME_GET_RUNNER_TOKEN_PYTHON")
	
	
	# TODO: turn batch_copy_issues into variable
	conda_environments=$(conda env list) 
	
	if [ $(lines_contain_string "$CONDA_ENVIRONMENT_NAME" "\${conda_environments}") == "FOUND" ]; then
		#cd get-gitlab-runner-registration-token && conda activate batch_copy_issues && python -m code.project1.src
		#cd get-gitlab-runner-registration-token && conda activate "batch_copy_issues" && python -m code.project1.src
		#cd get-gitlab-runner-registration-token && conda activate base && conda activate batch_copy_issues && python -m code.project1.src
		eval "$(conda shell.bash hook)"
		cd get-gitlab-runner-registration-token && conda deactivate && conda activate batch_copy_issues && python -m code.project1.src
		#cd get-gitlab-runner-registration-token && conda init batch_copy_issues && python -m code.project1.src
		# eval $(conda shell.bash hook)
	else
		cd get-gitlab-runner-registration-token && conda env create --file environment.yml && conda activate batch_copy_issues && python -m code.project1.src
	fi
	cd ..
}

# Downloads a repository into the root directory of this repository if the
#+ destination folder does yet exist
#+ TODO: write test for method
download_repository() {
	git_username=$1
	reponame=$2
	repo_url="https://github.com/"$git_username"/"$reponame".git"
	#echo "repo_url=$repo_url"
	if [ ! -d "$reponame" ]; then
		git clone $repo_url &&
		set +e
	fi
}

get_gitlab_server_runner_tokenV2() {
	GITURL="$GITLAB_SERVER_HTTP_URL"
	GITUSER="$gitlab_server_account"
	GITROOTPWD="$gitlab_server_password"
	
	# 1. curl for the login page to get a session cookie and the sources with the auth tokens
	body_header=$(curl -k -c gitlab-cookies.txt -i "${GITURL}/users/sign_in" -sS)
	
	# grep the auth token for the user login for
	#   not sure whether another token on the page will work, too - there are 3 of them
	csrf_token=$(echo $body_header | perl -ne 'print "$1\n" if /new_user.*?authenticity_token"[[:blank:]]value="(.+?)"/' | sed -n 1p)
	
	# 2. send login credentials with curl, using cookies and token from previous request
	output=$(curl -sS -k -b gitlab-cookies.txt -c gitlab-cookies.txt "${GITURL}/users/sign_in" \
		--data "user[login]=${GITUSER}&user[password]=${GITROOTPWD}" \
		--data-urlencode "authenticity_token=${csrf_token}"  -o /dev/null)
	
	# 3. send curl GET request to gitlab runners page to get registration token
	body_header=$(curl -sS -k -H 'user-agent: curl' -b gitlab-cookies.txt "${GITURL}/admin/runners" -o gitlab-header.txt)
	
	reg_token=$(cat gitlab-header.txt | perl -ne 'print "$1\n" if /code id="registration_token">(.+?)</' | sed -n 1p)
	echo $reg_token
}


get_gitlab_server_runner_tokenV3() {
	source src/hardcoded_variables.txt
	export GITURL="$GITLAB_SERVER_HTTP_URL"
	#read  -p "GITURL=$GITURL"
	export GITUSER="$gitlab_server_account"
	#read  -p "GITUSER=$GITUSER"
	export GITROOTPWD="$gitlab_server_password"
	#read  -p "GITROOTPWD=$GITROOTPWD"
	
	# 1. curl for the login page to get a session cookie and the sources with the auth tokens
	body_header=$(curl -k -c gitlab-cookies.txt -i "${GITURL}/users/sign_in" -sS)
	#read  -p "body_header=$body_header"
	
	# grep the auth token for the user login for
	#   not sure whether another token on the page will work, too - there are 3 of them
	csrf_token=$(echo $body_header | perl -ne 'print "$1\n" if /new_user.*?authenticity_token"[[:blank:]]value="(.+?)"/' | sed -n 1p)
	
	# 2. send login credentials with curl, using cookies and token from previous request
	output=$(curl -sS -k -b gitlab-cookies.txt -c gitlab-cookies.txt "${GITURL}/users/sign_in" \
		--data "user[login]=${GITUSER}&user[password]=${GITROOTPWD}" \
		--data-urlencode "authenticity_token=${csrf_token}"  -o /dev/null)
	
	# 3. send curl GET request to gitlab runners page to get registration token
	body_header=$(curl -sS -k -H 'user-agent: curl' -b gitlab-cookies.txt "${GITURL}/admin/runners" -o gitlab-header.txt)
	reg_token=$(cat gitlab-header.txt | perl -ne 'print "$1\n" if /code id="registration_token">(.+?)</' | sed -n 1p)
	echo $reg_token
}
