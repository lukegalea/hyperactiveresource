require File.dirname(__FILE__) + '/spec_helper'
require RAILS_ROOT + '/vendor/rails/activeresource/lib/active_resource/http_mock'
require "http_mock_mod"

class TestResource < HyperactiveResource
  self.site = 'http://localhost:3000' #This should never get called
end

class AnotherResource < HyperactiveResource
  self.site = 'http://localhost:3000' #This should never get called
end

class Race < HyperactiveResource
  self.site = 'http://localhost:3000' #This should never get called
end

describe "An active resource that extends abstract resource" do
  before(:each) do
    @it = TestResource.new
  end

  def reset_class_vars
    @it.instance_eval do
      self.skip_to_xml_for = []
      self.has_manys = []
      self.columns = []
      self.belong_tos = []
      self.nested_resources = []
    end
  end

  def mock_xml(type = 'blah')
    {:id => 1, :name => type.to_s}.to_xml(:root => type.to_s)
  end

  def mock_post(url = '/test_resources.xml')
    ActiveResource::HttpMock.respond_to do |mock|
      mock.post url, {}, mock_xml, 200
    end
  end

  def mock_put(url = '/test_resources/1.xml')
    ActiveResource::HttpMock.respond_to do |mock|
      mock.put url, {}, mock_xml, 200
    end
  end

  it "should be able to find_by_something" do
    TestResource.should_receive(:find).with(:first, :params => { 'something' => 'SOMETHING' }).and_return("SOMETHING")
    TestResource.find_by_something('SOMETHING').should == "SOMETHING"
  end

  it "should be able to find_all_by_something" do
    TestResource.should_receive(:find).with(:all, :params => { 'something' => 'SOMETHING' }).and_return(["SOMETHING","ELSE"])
    TestResource.find_all_by_something('SOMETHING').should == ["SOMETHING","ELSE"]
  end

  it "should not have a nil site variable" do
    TestResource.site.should_not be_nil
  end

  it "should behave like active_record and have attributes= do an update rather than a replacement" do
    @it = TestResource.new( :a => 1 )
    @it.attributes = { 'b' => 2 } #Aah. it seems that you can't use a symbol when you do this
    @it.a.should == 1
    @it.b.should == 2
  end

  it "should have a save! method that behaves like active_record and raises as exception if validation fails remotely" do
    ActiveResource::HttpMock.respond_to do |mock|
      mock.post '/test_resources.xml', {}, "<errors><error>Field has invalid characters</error></errors>", 422
    end

    lambda { @it.save! }.should raise_error( RecordNotSaved )
  end

  it "should have a save! method that behaves like active_record and raises as exception if validation fails locally" do
    @it.instance_eval do
      def validate
        errors.add("field", "has invalid characters")
      end
    end

    lambda { @it.save! }.should raise_error( RecordNotSaved )
  end

  it "should do local validation before doing an http request" do
    reset_class_vars
    mock_post

    @it.should_receive(:validate).and_return(true)
    @it.save
  end

  it "'s to_xml should skip attributes that are in the skip list" do
    @it.instance_eval do
      self.skip_to_xml_for = [ :enrollments ]
      self.belong_tos = [] #Make sure gender isn't treated as a belong_tos for this spec
    end
    enrollment = mock(:enrollment)
    @it.enrollments = [ enrollment ]
    @it.gender = mock(:gender)

    enrollment.should_not_receive(:to_xml)
    @it.gender.should_receive(:to_xml).and_return( mock_xml(:gender) )

    @it.to_xml
  end

  it "'s to_xml should move id's from associated belong_to objects into blah_id" do
    @it.instance_eval do
      self.belong_tos = [ :gender ]
    end

    gender_id = '25'
    @it.gender = mock(:gender, :id => gender_id)

    @it.gender.should_not_receive(:to_xml)

    REXML::Document.new( @it.to_xml ).elements["//test-resource/gender-id"].text.should eql( gender_id )
  end

  #This is not ideal.. but that's the current spec due to errors serializing arrays of integers
  it "'s to_xml should ignore plural id fields (blah_ids) and assume that :blahs => [ :blah => { :id => will be populated" do
    @it.instance_eval do
      self.has_manys = [ :races ]
    end

    #race_1 = mock(:race, :id => 1)
    #race_2 = mock(:race, :id => 2)

    #@it.races = [race_1, race_2]
    #@it.race_ids = [race_1.id, race_2.id]
    @it.race_ids = [1, 2]

    @it.race_ids.should_not_receive(:to_xml)

    @it.to_xml
  end

  it "'s save should call before_save and after_save when save is called" do
    mock_post
    @it.should_receive(:before_save)
    @it.should_receive(:after_save)
    @it.save
  end

  it "'s save should call before_validate when validate is called" do
    mock_post
    @it.should_receive(:before_validate)
    @it.send(:validate)
  end

  it "'s valid? should clear errors and call validate" do
    @it.errors.should_receive(:clear)
    @it.should_receive(:validate)
    #@it.parent.should_receive(:valid?).and_return(:true) #It should call super
    @it.valid?.should be_true
  end

  it "'s save should save nested resources" do
    mock_post

    @it.instance_eval do
      self.skip_to_xml_for = [] #Make sure enrollments isn't skipped
      self.has_manys = [ :enrollments ]
      self.nested_resources = [ :enrollment ]
    end

    @it.enrollments = [ mock(:enrollment), mock(:enrollment) ]

    @it.enrollments.each do |enrollment|
      enrollment.should_receive(:to_xml).and_return( mock_xml(:enrollment) )
      enrollment.should_receive(:test_resource_id=).with(1) #An id of 1 will be assigned by the mock_post
      enrollment.should_receive(:save).and_return( true )
    end

    @it.save
  end

  it "'s update should update/save nested resources" do
    mock_put

    @it.instance_eval do
      self.skip_to_xml_for = [] #Make sure enrollments isn't skipped
      self.has_manys = [ :enrollments ]
      self.nested_resources = [ :enrollment ]
    end

    @it.id = 1
    @it.enrollments = [ mock(:enrollment, :id => 1), mock(:enrollment, :id => 2) ]

    @it.enrollments.each do |enrollment|
      enrollment.should_receive(:to_xml).and_return( mock_xml(:enrollment) )
      enrollment.should_receive(:test_resource_id=).with(1) #An id of 1 will be assigned by the mock_post
      enrollment.should_receive(:save).and_return( true )
    end

    @it.save
  end

  #TODO this doesn't work. It's not used either so it's commented out in both abstract_resource and it's spec
#  it "should let you define associations via belong_to :blah instead of belong_tos = [:blah]" do
#    @it.instance_eval do
#      self.belongs_to :bt1
#      self.belongs_to :bt2
#      self.has_many :hm1
#      self.has_many :hm2
#      self.has_one :ho1
#      self.has_one :ho2
#    end
#
#    @it.belong_tos.should eql([:bt1, :bt2])
#    @it.has_manys.should eql([:hm1, :hm2])
#    @it.has_ones.should eql([:ho1, :ho2])
#  end

  it "should store unique class inherited variables for nested_resource, belong_tos, etc for each class" do
    class_attributes = [:skip_to_xml_for, :has_manys, :belong_tos, :has_ones, :columns]
    test_values = [:something, :something_else]
    @it.instance_eval do
      class_attributes.each do |attribute|
        self.send("#{attribute}=", test_values)
      end
    end

    class_attributes.each do |attribute|
      @it.send(attribute).should eql( test_values )
    end

    @another = AnotherResource.new

    class_attributes.each do |attribute|
      @another.send(attribute).should be_empty
    end
  end

  it "should load an array of id values into a single comma delimeted string" do
    @it.instance_eval do
      self.has_manys = [ :races ]
    end

    @it = TestResource.new(:race_ids => [1,2,3,4])
    @it.race_ids.should eql("1,2,3,4")
  end

  it "should convert ids in a belongs_to into integers" do
    @it.instance_eval do
      self.belong_tos = [ :gender ]
    end

    @it = TestResource.new(:gender_id => "1")

    #TODO Should this work? It doesn't currently..
    #@it.gender_id = "1"
    @it.gender_id.should == 1
  end

  it "should not dup loaded attributes" do
    gender = mock(:gender)
    @it = TestResource.new(:gender => gender)
    @it.gender.should === gender
  end

  it "should let you set an attribute using a setter method if defined as a column" do
    @it.instance_eval do
      self.columns = [ :something ]
    end

    test_value = 'blah'
    @it.something = test_value
    @it.attributes['something'].should === test_value #It's not an indifferent hash so only strings work!! Stupid active_resource.
  end

  it "should return nil if a column getter is called rather than method_missing as in ActiveResource" do
    @it.instance_eval do
      self.columns = [ :something ]
    end

    @it.something.should be_nil
  end

  it "should return nil if a belong_to column's id getter is called rather than method_missing as in ActiveResource" do
    @it.instance_eval do
      self.columns = [] #You shouldn't need the column specified, it should infer from the belong_tos
      self.belong_tos = [ :something ]
    end

    @it.something_id.should be_nil
  end

  it "should return [] if a has_many's ids getter is called rather than method_missing as in ActiveResource" do
    @it.instance_eval do
      self.columns = [] #You shouldn't need the column specified, it should infer from the belong_tos
      self.has_manys = [ :somethings ]
    end

    @it.something_ids.should == []
  end

  it "'s has_many accessors should return [] when ids is set to an empty string or nil" do
    @it.instance_eval do
      self.columns = []
      self.has_manys = [ :somethings ]
    end

    @it.something_ids = ''
    @it.somethings.should == []

    @it.something_ids = nil
    @it.somethings.should == []
  end

  it "should find a belongs_to if given only an id" do
    @it.instance_eval do
      self.belong_tos = [ :gender ]
    end

    @it.gender_id = 1

    Object.const_set('Gender', Class.new)
    gender = mock(:gender)
    Gender.should_receive(:find).with(@it.gender_id).and_return(gender)

    @it.gender.should === gender
  end

  it "should not find a belongs_to if the id is empty" do
    @it.instance_eval do
      self.belong_tos = [ :gender ]
    end

    @it.gender_id = nil
    @it.gender.should be_nil

    @it.gender_id = ""
    @it.gender.should be_nil
  end

  it "should return the id for belongs_to if given only the object" do
    @it.instance_eval do
      self.belong_tos = [ :gender ]
    end

    gender = mock(:gender, :id => 3)

    @it.gender = gender
    @it.gender_id.should eql( gender.id )
  end

  it "should return ids for a has_many if given only the objects" do
    @it.instance_eval do
      self.has_manys = [ :races ]
    end

    race = mock(:race, :id => 1)

    @it.races = [race,race,race]
    @it.race_ids.should eql([race.id,race.id,race.id])
  end

  it "should return the objects for a has_many if given only the ids" do
    @it.instance_eval do
      self.has_manys = [ :races ]
    end

    race_ids = [1,2,3]
    @it.race_ids = race_ids

    race = mock(:race)

    race_ids.each { |race_id| Race.should_receive(:find).with(race_id).and_return(race) }

    @it.races.should eql([race,race,race])
  end

  it "should find the object for a has_one given only the id" do
    @it.instance_eval do
      self.has_ones = [ :dog ]
    end

    @it.id = 1

    Object.const_set('Dog', Class.new)
    dog = mock(:dog)
    Dog.should_receive(:find_by_test_resource_id).with(@it.id).and_return(dog)
    @it.dog.should === dog
  end

  it "should raise an exception if a bad class method is called" do
    #This is testing that our dynamic find_by_blah isn't wrecking anything
    lambda { TestResource.something_that_does_not_exist }.should raise_error
  end
end
