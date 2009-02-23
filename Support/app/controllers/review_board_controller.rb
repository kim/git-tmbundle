class ReviewBoardController < ApplicationController

  def index
    upstream = "master" # TODO: what if upstream is a different branch?
    current_branch = git.branch.current.name

    commits_against_upstream = git.command("log", "--abbrev-commit", "--pretty=oneline", "#{upstream}..#{current_branch}").split("\n")

    defaults = {}
    defaults[:summary] = unless commits_against_upstream.size > 1
      commits_against_upstream.first
    else
      "Changes in #{current_branch} against #{upstream}"
    end
    defaults[:description] = "Combined diff of the following commits:\n\n" + commits_against_upstream.join("\n") if commits_against_upstream.size > 1
    defaults[:server] = git.command("config", "--get", "reviewboard.url")
    defaults[:branch] = current_branch
    defaults[:parent] = upstream
    defaults[:open_browser] = true

    puts "posting review...<br />"
    flush
    do_post_review(defaults)
  end

  def post_review
    do_post_review(params)
  end

  protected

    def do_post_review(options = {})
      cmd = ["cd #{e_sh git.path} &&"]
      cmd << File.expand_path(File.join(e_sh(ROOT), '/bin/post-review'))
      cmd << "--summary=\"#{escape_quotes options[:summary]}\""
      cmd << "--description=\"#{escape_quotes options[:description]}\""
      cmd << "--branch=#{options[:branch]}"
      cmd << "--parent=#{options[:parent]}" if options[:parent]
      cmd << "--target-groups=#{options[:groups]}" if options[:groups]
      cmd << "--target-people=#{options[:people]}" if options[:people]
      cmd << "--server=\"#{options[:server]}\"" if options[:server] and not options[:server].empty?
      cmd << "--open" if options[:open_browser]

      cmd = cmd.join(" ")
      TextMate::Process.run(cmd) do |out|
        puts out
      end
    end

    def escape_quotes(str)
      str.gsub("\"", "\\\"")
    end
end
