class ReviewBoardController < ApplicationController

  def index
    upstream = "master" # TODO: what if upstream is a different branch?
    current_branch = git.branch.current.name

    commits_against_upstream = git.command("log", "--abbrev-commit", "--pretty=oneline", "#{upstream}..#{current_branch}").split("\n")

    @summary = unless commits_against_upstream.size > 1
      commits_against_upstream.first
    else
      "Changes in #{current_branch} against #{upstream}"
    end
    @description = "Combined diff of the following commits:\n\n" + commits_against_upstream.join("\n") if commits_against_upstream.size > 1
    @server = git.command("config", "--get", "reviewboard.url")

    render "post_review"
  end

  def post_review
    cmd = ["cd #{e_sh git.path} &&"]
    cmd << File.expand_path(File.join(e_sh(ROOT), '/bin/post-review'))
    cmd << e_sh("--summary='#{params[:summary]}'")
    cmd << e_sh("--description='#{params[:description]}'")
    cmd << e_sh("--branch='#{params[:branch]}'")
    cmd << e_sh("--target-groups='#{params[:groups]}'") if params[:groups]
    cmd << e_sh("--target-people='#{params[:people]}'") if params[:people]
    cmd << e_sh("--server='#{params[:server]}'") if params[:server]
    cmd << "--open" if params[:open_browser]

    cmd = cmd.join(" ")
    TextMate::Process.run(cmd) do |out|
      puts out
    end
  end
end
