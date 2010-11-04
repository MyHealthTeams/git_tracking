require 'git_tracking'
require 'ruby-debug'

describe GitTracking do
  before(:all) do
    @original_git_author = `git config --global user.name`.chomp
  end

  after(:all) do
    system "git config --global user.name '#{@original_git_author}'"
    File.delete("foo.txt") if File.exists?("foo.txt")
  end

  it ".pre_commit should call detect_debuggers and detect_incomplete_merges" do
    GitTracking.should_receive(:detect_debuggers)
    GitTracking.should_receive(:detect_incomplete_merges)
    GitTracking.pre_commit
  end


  describe ".story" do
    before do
      GitTracking.class_eval{@story = nil}
    end

    it "should require a story" do
      the_story = mock('story', :name => 'Best feature evar', :id => 12345)
      GitTracking.stub(:story_id).and_return(nil)
      GitTracking.class_eval {@story = nil}
      GitTracking.highline.should_receive(:ask).with("Please enter a valid Pivotal Tracker story id: ", an_instance_of(Proc)).and_return(the_story)
      GitTracking.story.should == the_story
    end

    it "should not prompt once a story has been confirmed" do
      the_story = mock('story', :name => 'Best feature evar', :id => 12345)
      GitTracking.class_eval {@story = the_story}
      GitTracking.should_not_receive(:highline)
      GitTracking.story.should == the_story
    end

    it "should allow you to enter an alternate story when it finds a story_id" do
      the_story = mock('story', :name => 'Best feature evar', :id => 12345)
      GitTracking.stub(:story_id).and_return(the_story.id)
      GitTracking.stub(:get_story).and_return(the_story)
      GitTracking.highline.should_receive(:say).
        with("Found a valid story id in your branch or commit: 12345 - Best feature evar")
      GitTracking.highline.should_receive(:ask).
        with("Hit enter to confirm story id 12345, or enter some other story id: ", an_instance_of(Proc)).
        and_return(the_story)
      GitTracking.story.should == the_story
    end
  end

  describe ".story_id" do
    before(:each) do
      GitTracking.stub(:check_story_id).and_return(true)
      GitTracking.class_eval{@story_id = nil}
    end

    it "should check the commit message for a story id" do
      GitTracking.stub!(:commit_message).and_return("54261 - Fixing Javascript")
      GitTracking.story_id.should == '54261'
    end

    it "should check the branch name for a story id" do
      GitTracking.stub!(:commit_message).and_return("Fixing Javascript")
      GitTracking.stub!(:branch).and_return("64371-js-bug")
      GitTracking.story_id.should == '64371'
    end

    it "should check the .git/config file for the last story id" do
      GitTracking.stub!(:commit_message).and_return("Fixing Javascript")
      GitTracking.config.stub!(:git).and_return({:last_api_key => "fdskah32891", :last_story_id => '35236'})
      GitTracking.story_id.should == '35236'
    end

    it "should verify the story_id with the pivotal tracker API" do
      GitTracking.stub!(:commit_message).and_return("Generating 55654 monkeys")
      GitTracking.stub!(:branch).and_return("64371-js-bug")
      GitTracking.should_receive(:check_story_id).with('55654').and_return(false)
      GitTracking.should_receive(:check_story_id).with('64371').and_return(true)
      GitTracking.story_id.should == "64371"
    end
  end

  describe ".extract_story_id" do
    it "should extract any number that is 5 digits or longer and return it" do
      GitTracking.stub(:check_story_id).and_return(true)
      GitTracking.extract_story_id("45674 - The best feature evar").should == "45674"
      GitTracking.extract_story_id("90873 - The best feature evar").should == "90873"
    end

    it "should return nil if there is no number that is 5 digits or longer" do
      GitTracking.stub(:check_story_id).and_return(true)
      GitTracking.extract_story_id("The best feature evar").should be_nil
    end

    it "should return nil if it's not a valid Pivotal Tracker story id" do
      GitTracking.stub(:check_story_id).and_return(false)
      GitTracking.extract_story_id("45674 - The best feature evar").should be_nil
    end
  end

  describe ".check_story_id" do
    before(:each) do
      GitTracking.stub(:api_key).and_return(5678)
    end

    it "should return true for story id that can be found in tracker" do
      PivotalTracker::Project.stub(:find).and_return(mock("project"))
      GitTracking.pivotal_project.should_receive(:stories).and_return(mock("stories", :find => mock("story")))
      GitTracking.check_story_id(5678).should be_true
    end

    it "should return false for a valid story id" do
      PivotalTracker::Project.stub(:find).and_return(mock("project"))
      GitTracking.pivotal_project.should_receive(:stories).and_return(mock("stories", :find => nil))
      GitTracking.check_story_id(5678).should be_false
    end
  end

  describe ".api_key" do
    it "should prompt for a pivotal login" do
      GitTracking.stub(:author).and_return("Steve & Ghost Co-Pilot")
      GitTracking.class_eval {@api_key = nil}
      GitTracking.highline.should_receive(:ask).with("Enter your PivotalTracker email: ").and_return("john@doe.com")
      GitTracking.highline.should_receive(:ask).with("Enter your PivotalTracker password: ").and_return("password")
      PivotalTracker::Client.should_receive(:token).with("john@doe.com", "password").and_return("0987654567")
      GitTracking.api_key.should == "0987654567"
    end

    it "should prompt you to enter an alternate pivotal login" do
      GitTracking.stub(:author).and_return("Steve & Ghost Co-Pilot")
      GitTracking.class_eval {@api_key = "0987654567"}
      GitTracking.highline.should_receive(:say).with("Found a pivotal api key: 0987654567")
      GitTracking.highline.should_receive(:ask).with("Hit enter to use the api key 0987654567, or enter your email to change it")
      GitTracking.api_key.should == "0987654567"
    end

    it "should allow you to enter an alternate pivotal login" do
      GitTracking.stub(:author).and_return("Steve & Ghost Co-Pilot")
      GitTracking.class_eval {@api_key = "0987654567"}
      GitTracking.highline.should_receive(:say).with("Found a pivotal api key: 0987654567")
      GitTracking.highline.should_receive(:ask).with("Hit enter to use the api key 0987654567, or enter your email to change it").and_return("john@doe.com")
      GitTracking.highline.should_receive(:ask).with("Enter your PivotalTracker password: ").and_return("password")
      PivotalTracker::Client.should_receive(:token).with("john@doe.com", "password").and_return("0987654567")
      GitTracking.api_key.should == "0987654567"
    end
  end

  describe ".get_story" do
    before(:each) do
      GitTracking.stub(:api_key).and_return(5678)
    end

    it "should return true for story id that can be found in tracker" do
      story = mock("story")
      PivotalTracker::Project.stub(:find).and_return(mock("project"))
      GitTracking.pivotal_project.should_receive(:stories).and_return(mock("stories", :find => story))
      GitTracking.get_story(5678).should == story
    end

    it "should return false for a valid story id" do
      PivotalTracker::Project.stub(:find).and_return(mock("project"))
      GitTracking.pivotal_project.should_receive(:stories).and_return(mock("stories", :find => nil))
      GitTracking.get_story(5678).should be_nil
    end
  end

  describe ".author" do
    it "should prompt for a author" do
      original_author = `git config --global user.name`.chomp
      system "git config --global --unset user.name"
      GitTracking.class_eval {@author = nil}
      GitTracking.highline.should_receive(:ask).with("Please enter the git author: ").and_return("Steve & Ghost Co-Pilot")
      GitTracking.author.should == "Steve & Ghost Co-Pilot"
    end

    it "should allow you to enter an alternate author" do
      GitTracking.class_eval {@author = "Steve & Ghost Co-Pilot"}
      GitTracking.highline.should_receive(:say).with("git author set to: Steve & Ghost Co-Pilot")
      GitTracking.highline.should_receive(:ask).with("Hit enter to confirm author, or enter new author: ").and_return("")
      GitTracking.author.should == "Steve & Ghost Co-Pilot"
    end
  end

  describe ".prepare_commit_msg" do
    it "should get the message" do
      old_argv = ARGV
      File.open("foo.txt", "w") do |f|
        f.print "My awesome commit msg!"
      end
      ARGV = ["foo.txt"]
      GitTracking.stub(:story_info).and_return "[#12345] Best feature evar"
      GitTracking.prepare_commit_msg
      commit_msg = File.open("foo.txt", "r").read
      commit_msg.should == <<STRING
[#12345] Best feature evar

  - My awesome commit msg!
STRING
      ARGV = old_argv
    end

    it "should call story_info and author" do
      ARGV = ["foo.txt"]
      GitTracking.should_receive(:story_info).and_return "[#12345] Best feature evar"
      GitTracking.should_receive(:author)
      GitTracking.prepare_commit_msg
    end
  end

  it ".story_info should format the story info appropriately" do
    GitTracking.should_receive(:story).twice.and_return(mock("story", :name => "Best feature evar", :id => "12345"))
    GitTracking.story_info.should == "[#12345] Best feature evar"
  end
end
