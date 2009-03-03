require 'uri'
require ENV['TM_SUPPORT_PATH'] + '/lib/tm/process.rb'
require ENV['TM_SUPPORT_PATH'] + '/lib/ui'
require 'strscan'

%w[json/version json/pure/parser json/pure/generator json/common json/pure json].each do |filename|
  require File.dirname(__FILE__) + "/../../lib/#{filename}.rb"
end

class ReviewBoardController < ApplicationController

  REVIEWBOARD_COOKIE_NAME = "~/.reviewboard.cookie"

  class LoginRequiredError < RuntimeError; end
  class UpstreamRequiredError < RuntimeError; end
  class RepositoryIdRequiredError < RuntimeError; end

  def index

    current_branch = git.branch.current.name

    # try to get reviewboard url from config, otherwise ask user
    begin
      url ||= git.command("config", "--get", "reviewboard.url").strip
      raise URI::InvalidURIError, "Empty.." if url.empty?
      @reviewboard_url = URI.parse(url)
      @reviewboard_url = @reviewboard_url.to_s.chomp("/")
    rescue URI::InvalidURIError
      url = ask_config( "reviewboard.url", "Which Reviewboard?", "Reviewboard URL:" ) || return
      retry
    end

    # try to get the upstream from config, otherwise ask user (default: master)
    begin
      @upstream ||= git.command("config", "--get", "reviewboard.upstream").strip
      raise ReviewBoardController::UpstreamRequiredError, "Empty upstream.." if @upstream.empty?
    rescue ReviewBoardController::UpstreamRequiredError
      @upstream = ask_config( "reviewboard.upstream", "Which Upstream to diff?", "Upstream branch:" ) || return
      retry
    end

    opts = {}
    begin
      @repository_id ||= git.command("config", "--get", "reviewboard.repositoryid").strip
      raise ReviewBoardController::RepositoryIdRequiredError, "No repository id in config" if @repository_id.empty?
      opts[:repository_id] = @repository_id.to_s
    rescue ReviewBoardController::RepositoryIdRequiredError
      @repository_id = ask_repositoryid() || return
      retry
    end

    response = create_new_request(opts)
    review_request_id = response["review_request"]["id"]
    upload_diff(review_request_id, git.command("diff", "--no-color", "--no-prefix", @upstream))

    `open #{@reviewboard_url}/r/#{review_request_id}`
    puts "Review sent. <a href=\"#{@reviewboard_url}/r/#{review_request_id}\">Click here to edit your review request</a>"
  end

  def reconfigure
    @reviewboard_url = ask_config_value( "reviewboard.url", "Which Reviewboard?", "Reviewboard URL:" )
    ask_user_and_password_and_login()
    ask_config_value( "reviewboard.upstream", "Which Upstream to diff?", "Upstream branch:" ) || return
    ask_repositoryid() || return
    puts "<p>Configuration updated!</p>"
  end

  private

    def ask_config_value( value, title, label )
      url = git.command("config", "--get", value ).strip
      url = TextMate::UI.request_string(:title => title, :default => url, :prompt => label ).strip
      unless url.empty?
        git.command("config", value, url)
        return url
      else
        puts "<p>#{value} can't be empty, aborting...</p>"
        return nil
      end
    end

    def ask_repositoryid( store=false, read=true )
      # Get available repositories
      items = (get_available_repositories || []).map { |x| "##{x['id']}: #{x['name']}" }
      selection = TextMate::UI.request_item(:items => items, :title => "Choose to which repository you want to publish?", :prompt => "Repository:").strip
      if selection =~ /^#(\d*):.*/
        repository_id = $1.to_s
        git.command("config", "--add", "reviewboard.repositoryid", repository_id )
        return repository_id
      else
        puts "<p>No repository selected, aborting ...</p>"
        return nil
      end
    end

    def ask_user_and_password_and_login
      username = TextMate::UI.request_string(:title => "Login required", :prompt => "Enter username:")
      password = TextMate::UI.request_secure_string(:title => "Login required", :prompt => "Enter password:")

      raise "No username or password given, aborting..." if username.empty? and password.empty?
      File.delete( REVIEWBOARD_COOKIE_NAME ) if File.exists?( REVIEWBOARD_COOKIE_NAME )
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
        #TODO: Possible security issue, tmpfiles should be random and shall verify doesn't exist before
        files.keys.each do |key|
          File.open("/tmp/#{files[key][:filename]}", "wb") {|f| f.puts files[key][:content] }
        end

        cmd = "curl -v --cookie #{REVIEWBOARD_COOKIE_NAME} --cookie-jar #{REVIEWBOARD_COOKIE_NAME}"
        params.each do |name, value|
          name = name.to_s
          value = value.to_s
          cmd << " #{files.empty? ? "--data" : "--form-string"} \"#{URI.escape name}=#{URI.escape value}\" " unless value.empty?
        end

        files.keys.each {|key| cmd << " --form \"#{key}=@/tmp/#{files[key][:filename]}\" "}
        cmd << " #{@reviewboard_url}/#{path}"
        response = TextMate::Process.run(cmd)
        response = JSON.parse(response[0])
        raise ReviewBoardController::LoginRequiredError, "Require login" if response_requires_login( response, true )
        return response
      rescue ReviewBoardController::LoginRequiredError
        retry
      end
    end
end
