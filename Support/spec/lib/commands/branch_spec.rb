require File.dirname(__FILE__) + '/../../spec_helper'

describe Git::Branch do
  before(:each) do
    Git.reset_mock!
    
    @branch = Git::Branch.new
    Git.command_response["branch", "-r"] = "  origin/master\n  origin/task"
    Git.command_response["branch"] = "* master\n  task"
    
    @request_branch_expectation = lambda { |response|
      TextMate::UI.should_receive(:request_item).with(:title => "Delete Branch", :prompt => "Select the branch to delete:", :items => ["master", "task", "origin/master", "origin/task"]).and_return(response)
    }
  end
  include SpecHelpers
  
  describe "when deleting local branches" do
    describe "when branch is not fully merged" do
      before(:each) do
        Git.command_response["branch", "-d", "task"] = "error: branch 'task' is not a strict subset of HEAD\nnot going to allow you to delete it!"
        Git.command_response["branch", "-D", "task"] = "Deleted branch task."
        @really_delete_params = [:warning, "Warning", "Branch 'task' is not a strict subset of your current HEAD (it has unmerged changes)\nReally delete it?", 'Yes', 'No']
      end
      
      it "Ask you if you'd like to delete the branch, and then delete it with -D if yes" do
        @request_branch_expectation.call("task")
        TextMate::UI.should_receive(:alert).with(*@really_delete_params).and_return("Yes")
        TextMate::UI.should_receive(:alert).with(:informational, "Delete branch", "Deleted branch task.", "OK")
        @branch.run_delete
      end
      
      it "allow you to cancel" do
        @request_branch_expectation.call("task")
        TextMate::UI.should_receive(:alert).with(*@really_delete_params).and_return("No")
        @branch.run_delete
      end
    end
    
    describe "when branch is fully merged" do
      before(:each) do
        Git.command_response["branch", "-d", "task"] = "Deleted branch task."
      end
      
      it "should delete" do
        @request_branch_expectation.call("task")
        TextMate::UI.should_receive(:alert).with(:informational, "Success", "Deleted branch task.", "OK").and_return("No")
        @branch.run_delete
      end
    end
  end
  
  describe "when deleting remote branches" do
    it "should delete a remote branch via a push" do
      @request_branch_expectation.call("origin/task")
      Git.command_response["push", "origin", ":task"] = <<EOF
deleting 'refs/heads/task'
 Also local refs/remotes/origin/task
refs/heads/task: d8b368361ebdf2c51b78f7cfdae5c3044b23d189 -> deleted
Everything up-to-date
EOF
      
      TextMate::UI.should_receive(:alert).with(:informational, "Success", "Deleted remote branch origin/task.", "OK").and_return("No")
      @branch.run_delete
      
      Git.commands_ran.should include(["push", "origin", ":task"])
    end
    
    it "should show a message when server reports branch doesn't exist" do
      @request_branch_expectation.call("origin/task")
      Git.command_response["push", "origin", ":task"] = <<EOF
error: dst refspec origin does not match any existing ref on the remote and does not start with refs/.
fatal: The remote end hung up unexpectedly
error: failed to push to '../origin/'
EOF
      TextMate::UI.should_receive(:alert).with(:warning, "Delete branch failed!", "The source 'origin' reported that the branch 'task' does not exist.\nTry running the prune remote stale branches command?", "OK")
      @branch.run_delete
    end
  end
end