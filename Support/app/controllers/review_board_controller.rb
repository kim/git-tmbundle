require 'uri'
require ENV['TM_SUPPORT_PATH'] + '/lib/tm/process.rb'
require ENV['TM_SUPPORT_PATH'] + '/lib/ui'

require 'rubygems'
require 'json'
require 'net/http'

class ReviewBoardController < ApplicationController

  class LoginRequiredError < RuntimeError; end
  class RepositoryIdRequiredError < RuntimeError; end

  def index
    current_branch = git.branch.current.name

    # try to get reviewboard url from config, otherwise ask user
    begin
      url ||= git.command("config", "--get", "reviewboard.url").strip
      raise URI::InvalidURIError, "Empty.." if url.empty?
      @reviewboard_url = URI.parse(url)
      @reviewboard_url = @reviewboard_url.to_s.chomp!("/")
    rescue URI::InvalidURIError
      url = TextMate::UI.request_string(:title => "Which Reviewboard?", :prompt => "Reviewboard URL:").strip
      unless url.empty?
        git.command("config", "reviewboard.url", url)
        retry
      else
        puts "<p>So you don't wanna tell me which URL?</p>"
        return
      end
    end

    # try to get the upstream from config, otherwise ask user (default: master)
    begin
      @upstream ||= git.command("config", "--get", "reviewboard.upstream").strip
      raise URI::InvalidURIError, "Empty upstream.." if @upstream.empty?
    rescue URI::InvalidURIError
      @upstream = TextMate::UI.request_string(:title => "Which Upstream to diff?", :default => @upstream.empty? ? "master" : @upstream, :prompt => "Upstream branch:").strip
      unless @upstream.empty?
        # Todo: Check that upstream actually exists?
        git.command("config", "reviewboard.upstream", @upstream)
        retry
      else
        puts "<p>Upstream can't be empty, aborting...</p>"
        return
      end
    end

    opts = {}
    begin
      @repository_id ||= git.command("config", "--get", "reviewboard.repositoryid").strip
      raise ReviewBoardController::RepositoryIdRequiredError, "No repository id in config" if @repository_id.empty?
      opts[:repository_id] = @repository_id.to_s
    rescue ReviewBoardController::RepositoryIdRequiredError
      # Get available repositories
      items = (get_available_repositories || []).map { |x| "##{x['id']}: #{x['name']}" }
      selection = TextMate::UI.request_item(:items => items,  :title => "Choose to which repository you want to publish?", :prompt => "Repository:").strip
      if selection =~ /^#(\d*):.*/
        @repository_id = $1.to_s
        git.command("config", "--add", "reviewboard.repositoryid", @repository_id )
        retry
      else
        puts "<p>No repository selected, aborting ...</p>"
        puts "<p>Please use git config --add reviewboard.repository_id|reviewboard.repository_path &lt;ID|path&gt; if you don't get a list of available repositories"
        return
      end
    end

    response = create_new_request(opts)

    git.command("config", "reviewboard.repository_id", response["review_request"]["repository"]["id"])
    review_request_id = response["review_request"]["id"]
    upload_diff(review_request_id, git.command("diff", "--no-color", "--no-prefix", @upstream))

    `open #{@reviewboard_url}/r/#{review_request_id}`
    puts "Review sent. <a href=\"#{@reviewboard_url}/r/#{review_request_id}\">Click here to edit your review request</a>"
  end

  private

    def ask_user_and_password_and_login
      username = TextMate::UI.request_string(:title => "Login required", :prompt => "Enter username:")
      password = TextMate::UI.request_secure_string(:title => "Login required", :prompt => "Enter password:")

      raise "No username or password given, aborting..." if username.empty? and password.empty?
      login(username, password)
    end

    def response_requires_login( response, ask_for_user_password=false )
      if response["stat"] == "fail"
        if response["err"]["code"] == 103
          ask_user_and_password_and_login() if ask_for_user_password
          return true
        else
          raise "Unknown error: #{response["err"]}"
        end
      end
      return false
    end

    def create_new_request(data)
      puts "<p>Creating new review request...</p>"
      api_post("api/json/reviewrequests/new/", data)
    end

    def get_available_repositories
      puts "<p>Grabbing available repositories...</p>"
      response = api_post("api/json/repositories/", {} )
      response["repositories"] || []
    end

    def login(username, password)
      puts "<p>Logging in...</p>"
      api_post("api/json/accounts/login/", { :username => username, :password => password })
    end

    def upload_diff(review_request, diff)
      puts "<p>uploading diff..</p>"
      api_post("api/json/reviewrequests/#{review_request}/diff/new/", {:basedir => "/"}, { "path" => { :filename => "output.diff", :content => diff }})
    end

    def api_post(path, params, files = {}, headers = {})

      begin
        files.keys.each do |key|
          File.open("/tmp/#{files[key][:filename]}", "wb") {|f| f.puts files[key][:content] }
        end

        cmd = "curl -v --cookie ~/.reviewboard.cookie --cookie-jar ~/.reviewboard.cookie"
        params.each do |name, value|
          name = name.to_s
          value = value.to_s
          cmd << " #{files.empty? ? "--data" : "--form-string"} \"#{URI.escape name}=#{URI.escape value}\" " unless value.empty?
        end

        files.keys.each {|key| cmd << " --form \"#{key}=@/tmp/#{files[key][:filename]}\" "}

        cmd << " #{@reviewboard_url}/#{path}"

#       puts "<p>cmd was #{cmd}</p>"
        response = TextMate::Process.run(cmd)
#       puts "<p>response was #{response}</p>"
        response = JSON.parse(response[0])
        raise ReviewBoardController::LoginRequiredError, "Require login" if response_requires_login( response, true )
        return response
      rescue ReviewBoardController::LoginRequiredError
        retry
      end
    end
end
