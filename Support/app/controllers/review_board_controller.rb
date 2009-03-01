require 'uri'
require ENV['TM_SUPPORT_PATH'] + '/lib/tm/process.rb'
require ENV['TM_SUPPORT_PATH'] + '/lib/ui'

require 'rubygems'
require 'json'

class ReviewBoardController < ApplicationController

  def index
    upstream = "master" # TODO: what if upstream is a different branch?
    current_branch = git.branch.current.name

    begin
      url ||= git.command("config", "--get", "reviewboard.url").strip
      raise URI::InvalidURIError, "Empty.." if url.empty?
      @reviewboard_url = URI.parse(url)
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

    # puts "<p>reviewboard url: #{@reviewboard_url}</p>"

    opts = {}
    opts[:repository_id] = git.command("config", "--get", "reviewboard.repository_id").strip
    if opts[:repository_id].empty?
      opts[:repository_path] = git.command("config", "--get", "reviewboard.repository_path")
      opts[:repository_path] = git.command("remote", "show", "-n","origin").scan(/\s+URL: (.*)$/).flatten.first if opts[:repository_path].empty?
      opts[:repository_path].strip

      if opts[:repository_path].empty?
        puts "<p>No repository ID or path found, please use git config --add reviewboard.repository_id|reviewboard.repository_path &lt;ID|path&gt;"
        return
      end
    end

    response = create_new_request(opts)

    git.command("config", "reviewboard.repository_id", response["review_request"]["repository"]["id"])
    review_request_id = response["review_request"]["id"]
    upload_diff(review_request_id, git.command("diff", "--no-color", "--no-prefix", upstream))
    raise "Huh?"

    # `open #{@reviewboard_url}/r/#{review_request_id}`
    puts "<a href=\"#{@reviewboard_url}/r/#{review_request_id}\">clickety</a>"
    raise "WTF?"
  end

  private
    def create_new_request(data)
      puts "creating new review request..."
      response = api_post("api/json/reviewrequests/new/", data)
      if response["stat"] == "fail"
        if response["err"]["code"] == 103
          username = TextMate::UI.request_string(:title => "Login required", :prompt => "Enter username:")
          password = TextMate::UI.request_secure_string(:title => "Login required", :prompt => "Enter password:")
          login(username, password)
          response = create_new_request(opts)
        else
          raise "Unknown error: #{response["err"]}"
        end
      end
      response
    end

    def login(username, password)
      puts "logging in..."
      api_post("api/json/accounts/login/", { :username => username, :password => password })
    end

    def upload_diff(review_request, diff)
      puts "uploading diff.."
      api_post("api/json/reviewrequests/#{review_request}/diff/new/", {:basedir => "/"}, { "path" => { :filename => "output.diff", :content => diff }})
    end

    def api_post(path, params, files = {}, headers = {})

      files.keys.each do |key|
        File.open("/tmp/#{files[key][:filename]}", "wb") {|f| f.puts files[key][:content] }
      end

      cmd = "curl -v --cookie ~/.reviewboard.cookie --cookie-jar ~/.reviewboard.cookie"
      params.each do |name, value|
        name = name.to_s
        value = value.to_s
        cmd << " #{files.empty? ? "--data" : "--form"} \"#{URI.escape name}=#{URI.escape value}\" " unless value.empty?
      end

      files.keys.each {|key| cmd << " --form \"#{key}=@/tmp/#{files[key][:filename]}\" "}

      cmd << "#{@reviewboard_url}/#{path}"

      puts cmd
      response = TextMate::Process.run(cmd)
      p response
      JSON.parse(response[0])
    end
end
