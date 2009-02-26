require 'rubygems'
require 'curb'
require 'activesupport'
require ENV['TM_SUPPORT_PATH'] + "/lib/ui"

class ReviewBoardController < ApplicationController

  def index
    upstream = "master" # TODO: what if upstream is a different branch?
    current_branch = git.branch.current.name

    begin
      @reviewboard_url = URI.parse git.command("config", "--get", "reviewboard.url").strip
    rescue URI::InvalidURIError
      puts "<p>No reviewboad URL found, please use git config --add reviewboard.url &lt;URL&gt;</p>"
      return
    end

    puts "<p>reviewboard url: #{@reviewboard_url}</p>"

    opts = {}
    opts[:repository_id] = git.command("config", "--get", "reviewboard.repository_id").strip
    if opts[:repository_id].empty?
      opts[:repository_path] = git.command("config", "--get", "reviewboard.repository_path")
      opts[:repository_path] = git.command("remote", "show", "-n","origin").scan(/\s+URL: (.*)$/).flatten.first if opts[:repository_path].empty?
      opts[:repository_path].strip

      if opts[:repository_path].empty?
        puts "<p>No repository ID or path found, please use git config --add reviewboard.repository_id|reviewboard.repository_path &lt;ID|path&gt;"
        return
      else
        puts "<p>repository_path: '#{opts[:repository_path]}'</p>"
      end
    end

    response = create_new_request(opts)
    if response["stat"] == "fail"
      if response["err"]["code"] == 103
        username = TextMate::UI.request_string(:title => "Login required", :prompt => "Enter username:")
        password = TextMate::UI.request_secure_string(:title => "Login required", :prompt => "Enter password:")
        login(username, password)
        response = create_new_request(opts)
      end
    end
    git.command("config", , "reviewboard.repository_id", response["review_request"]["repository"]["id"])
    review_request_id = response["review_request"]["id"]
    upload_diff(review_request_id, git.command("diff", "--no-color", "--no-prefix", upstream))

    `open #{@reviewboard_url}/r/#{review_request_id}`
  end

  private
    def create_new_request(data)
      api_post("/api/json/reviewrequests/new/", data)
    end

    def login(username, password)
      api_post("api/json/accounts/login/", { :username => username, :password => password })
    end

    def upload_diff(review_request, diff)
      api_post("api/json/reviewrequests/%s/diff/new/" % review_request, )
    end

    def api_post(path, params, files, headers = {})
      c = Curl::Easy.new("#{@reviewboard_url.host}:#{@reviewboard_url.port}")
      c.multipart_form_post = true

      params = params.map do |name, value|
        Curl::PostField.content name, value
      end
      params += files.map do |filename, filedata|
        Curl::PostField.file
      end
      c.http_post(
        Curl::Post
      )
      response = Net::HTTP.start(@reviewboard_url.host, @reviewboard_url.port) do |http|
        headers["Cookie"] = @cookie if @cookie
        req = Net::HTTP::Post.new(path, headers)
        req.set_form_data(data)
        http.request(req)
      end
      @cookie = response['set-cookie']
      ActiveSupport::JSON.decode(response.body)
    end
end
