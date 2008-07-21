# Raised by ActiveRecord::Base.save! and ActiveRecord::Base.create! methods when record cannot be
# saved because record is invalid.
class AbstractRecordError < StandardError; end

# Raised by ActiveRecord::Base.save! and ActiveRecord::Base.create! methods when record cannot be
# saved because record is invalid.
class RecordNotSaved < AbstractRecordError; end

class HyperactiveResource < ActiveResource::Base
  # make sure attributes of ARES has indifferent_access
  def initialize(attributes = {})
    @attributes     = {}.with_indifferent_access
    @prefix_options = {}
    load(attributes)
  end                             
  
  #This is required to make it behave like ActiveRecord
  def attributes=(new_attributes)    
    attributes.update(new_attributes)
  end
  
  #This is also required to behave like ARec
  def save!
    validate
    ( errors.empty? && save ) || raise(RecordNotSaved)
  end 
  
  def to_xml(options = {})
    #RAILS_DEFAULT_LOGGER.debug("** Begin Dumping XML for #{self.class.name}:#{self.id}")    
    massaged_attributes = attributes.dup
    
    #Massage patient.id into patient_id (for every belongs_to) and    
    massaged_attributes.each do |key, value|
      if self.belong_tos.include? key.to_sym
        #RAILS_DEFAULT_LOGGER.debug("**** Moving #{key}.id into #{key}_id")        
        massaged_attributes["#{key}_id"] = value.id #TODO Should check respond_to and so on
        massaged_attributes.delete(key)       
      elsif key.to_s =~ /^.*_ids$/
        #RAILS_DEFAULT_LOGGER.warn("**** Deleting #{key}.id because we are using the non ids version")
        massaged_attributes.delete(key)        
      end
    end
    
    #Skip the things in the skip list
    massaged_attributes = massaged_attributes.reject do |key,value|
      skip_to_xml_for.include? key.to_sym
    end    
    
    xml = massaged_attributes.to_xml({:root => self.class.element_name}.merge(options))
    #RAILS_DEFAULT_LOGGER.debug("** End Dumping XML for #{self.class.name}:#{self.id}")
    xml
  end
    
  def save
    return false unless valid?
    before_save    
    successful = super
    if successful          
      after_save 
    end
    successful
  end    
  
  # make sure we can valid? new record  
  def valid? 
    errors.clear
    validate 
    super 
  end
  
  protected  
  
  def save_nested
    @saved_nested_resources = {}
    nested_resources.each do |nested_resource_name|
      resources = attributes[nested_resource_name.to_s.pluralize] 
      resources ||= send(nested_resource_name.to_s.pluralize)
      unless resources.nil?
        resources.each do |resource|
          @saved_nested_resources[nested_resource_name] = []
          #We need to set a reference from this nested resource back to the parent  

          fk = self.respond_to?("#{nested_resource_name}_options") ? self.send("#{nested_resource_name}_options")[:foreign_key]  : "#{self.class.name.underscore}_id"
          resource.send("#{fk}=", self.id)
          @saved_nested_resources[nested_resource_name] << resource if resource.save
        end
      end
    end
  end
  
  # Update the resource on the remote service.
  def update
    #RAILS_DEFAULT_LOGGER.debug("******** REST Call to CRMS: Updating #{self.class.name}:#{self.id}")
    #RAILS_DEFAULT_LOGGER.debug(caller[0..5].join("\n"))                             
    response = connection.put(element_path(prefix_options), to_xml, self.class.headers)
    save_nested
    load_attributes_from_response(response)
    merge_saved_nested_resources_into_attributes
    response
  end

  # Create (i.e., save to the remote service) the new resource.
  def create
    #RAILS_DEFAULT_LOGGER.debug("******** REST Call to CRMS: Creating #{self.class.name}:#{self.id}")
    #RAILS_DEFAULT_LOGGER.debug(caller[0..5].join("\n"))
    response = connection.post(collection_path, to_xml, self.class.headers)
    self.id = id_from_response(response) 
    save_nested
    load_attributes_from_response(response)
    merge_saved_nested_resources_into_attributes
    response
  end  
  
  ##These are just hooks for debugging
#  def self.find_every(options)
#    RAILS_DEFAULT_LOGGER.debug("******** REST Call to CRMS: Getting #{self.name}")
#    RAILS_DEFAULT_LOGGER.debug(caller[0..5].join("\n"))
#    super
#  end
#        
#  def self.find_one(options)
#    RAILS_DEFAULT_LOGGER.debug("******** REST Call to CRMS: Getting #{self.name}")
#    RAILS_DEFAULT_LOGGER.debug(caller[0..5].join("\n"))
#    super
#  end
#
#  def self.find_single(scope, options)
#    RAILS_DEFAULT_LOGGER.debug("******** REST Call to CRMS: Getting #{self.name}")
#    RAILS_DEFAULT_LOGGER.debug(caller[0..5].join("\n"))
#    super
#  end
  
  def merge_saved_nested_resources_into_attributes
    @saved_nested_resources.each_key do |nested_resource_name|
      attr_name = nested_resource_name.to_s.pluralize
      resource_list_before_merge = attributes[attr_name] || []
      attributes[attr_name] = resource_list_before_merge - @saved_nested_resources[nested_resource_name]
      attributes[attr_name] +=  @saved_nested_resources[nested_resource_name]
    end
    @saved_nested_resources = []
  end
  
  def id_from_response(response)
    # response['Location'][/\/([^\/]*?)(\.\w+)?$/, 1]
    Hash.from_xml(response.body).values[0]["id"]
  end            
  
  def after_save
  end
  
  def before_save
    before_save_or_validate
  end
  
  def before_validate
    before_save_or_validate
  end
  
  #TODO I don't like the way this works. If you override validate you have to remember to call before_validate or super..
  def validate
    before_validate
  end
    
  def before_save_or_validate
    #Do nothing
  end     
  
  class_inheritable_accessor :has_manys
  class_inheritable_accessor :has_ones
  class_inheritable_accessor :belong_tos
  class_inheritable_accessor :columns
  class_inheritable_accessor :skip_to_xml_for
  class_inheritable_accessor :nested_resources
  
  self.nested_resources = []
  self.has_manys = []
  self.has_ones = []
  self.belong_tos = []
  self.columns = []
  self.skip_to_xml_for = []

  #These don't work!
#  def self.belongs_to( name )
#    self.belong_tos << name
#  end
#    
#  def self.has_many( name )
#    self.has_manys << name
#  end
#  
#  def self.column( name )
#    self.columns << name
#  end 
      
#  When you call any of these dynamically inferred methods 
#  the first call sets it so it's no longer dynamic for subsequent calls
#  Ie. If there is residencies but no residency_ids
#  then when you first call residency_ids it'll pull the residency ids into the residency_ids..
#  But future changes aren't kept in sync (like ActiveRecord.. mostly)
  def method_missing(name, *args)
    return super if attributes.keys.include? name.to_s         
    
    case name
    when *self.columns
      return column_getter_method_missing(name)
    when *self.belong_tos
      return belong_to_getter_method_missing(name)
    when *self.belong_to_ids
      return belong_to_id_getter_method_missing(name)
    when *self.has_manys
      return has_many_getter_method_missing(name)
    when *self.has_many_ids
      return has_many_ids_getter_method_missing(name)
    when *self.has_ones
      return has_one_getter_method_missing(name)      
    end                                     

    super
  end
  
  #Used by method_missing & load to infer setter & getter names from association names
  def has_many_ids    
    self.has_manys.map { |hm| "#{hm.to_s.singularize}_ids".to_sym }
  end
  
  #Used by method_missing & load to infer setter & getter names from association names
  def belong_to_ids
    self.belong_tos.map { |bt| "#{bt}_id".to_sym }
  end
  
  #Calls to column getter when there is no attribute for it, nor a previous set called it will return nil rather than freak out
  def column_getter_method_missing( name )
    self.call_setter(name, nil)
  end
  
  #Getter for a belong_to relationship checks if the _id exists and dynamically finds the object
  def belong_to_getter_method_missing( name )
    #If there is a blah_id but not blah get it via a find
    association_id = self.send("#{name.to_s.underscore}_id")
    (association_id.nil? or ( association_id.respond_to? :empty? and association_id.empty? ) ) ? 
      nil : call_setter(name, name.to_s.camelize.constantize.send(:find, association_id ) )
  end
  
  #Getter for a belong_to's id will return the object.id if it exists
  def belong_to_id_getter_method_missing( name )
    #The assumption is that this will always be called with a name that ends in _id   
    association_name = remove_id name
    unless attributes[association_name].nil? #If there is the obj itself rather than the blah_id
      call_setter( name, self.send(association_name).id ) #Use the blah.id for blah_id
    else  
      column_getter_method_missing( name ) #call_setter( name, nil ) #Just like a column
    end
  end
  
  #If there is _ids, but not objects array the method missing for has_many will get each object via id. Otherwise it will return
  #an empty array (like active
  def has_many_getter_method_missing( name )
    association_ids = self.send("#{name.to_s.singularize.underscore}_ids")
    if association_ids.nil? or association_ids.empty?
      call_setter(name, []) #return
    else
      #If we have blah_ids and no blahs, get them all via finds
      associated_models = association_ids.collect do |associated_id| 
        name.to_s.singularize.camelize.constantize.send(:find, associated_id)
      end
      call_setter(name, associated_models) #return
    end
  end
  
  def has_many_ids_getter_method_missing( name )
    association_name = remove_id(name).pluralize #(residency_ids => residencies)
    unless attributes[association_name].nil?
      call_setter(name, self.send(association_name).collect(&:id) )
    else
      call_setter(name, [])
    end
  end
  
  def has_one_getter_method_missing( name )
    self.new? ? nil : 
      call_setter( name, name.to_s.camelize.constantize.send("find_by_#{self.class.name.underscore}_id", self.id) )
  end
  
  #Convenience method used by the method_missing methods
  def call_setter( name, value )
    self.send( "#{name}=", value )
  end
  
  #Chops the _id off the end of a method name to be used in method_missing
  def remove_id( name_with_id )
    name_with_id.to_s.gsub(/_ids?$/,'')
  end
  
  #There are lots of differences between active_resource's initializer and active_record's
  #ARec lets you pass a block 
  #Arec doesn't clone
  #Arec calls blah= on everything that's passed in.
  #Arec will turn a "1" into a 1 if it's in an ID column (or any integer for that matter)
  #This is a copy of the method out of ActiveResource::Base modified
  def load(attributes)
    raise ArgumentError, "expected an attributes Hash, got #{attributes.inspect}" unless attributes.is_a?(Hash)
    @prefix_options, attributes = split_options(attributes)
    attributes.each do |key, value|      
      @attributes[key.to_s] =
        case value
          when Array
            #BEGIN ADDITION TO AR::BASE
            load_array(key, value)
            #END ADDITION              
          when Hash
            resource = find_or_create_resource_for(key)
            resource.new(value)
          else
            #BEGIN ADDITION TO AR::BASE
            convert_to_i_if_id_field(key, value)
            #WAS: value #.dup rescue value #REMOVED FROM AR:BASE
            #END ADDITION                                                  
          end
      #BEGIN ADDITION TO AR::BASE
      call_attribute_setter(key, value)
      #END ADDITION
    end
    #BEGIN ADDITION TO AR::BASE
    result = yield self if block_given?
    #END ADDITION
    result || self
  end
  
  #Called by overriden load
  def load_array( key, value )
    if self.has_many_ids.include? key
      #This means someone has set blah_ids = [1,2,3]
      #Instead of being retarded like ActiveResource normally is,
      #Let's turn this into "1,2,3"
      value.join(',')
    else
      resource = find_or_create_resource_for_collection(key)
      value.map { |attrs| resource.new(attrs) }
    end
  end
  
  #Called by overriden load
  def convert_to_i_if_id_field( key, value )
    #This might be an id of an association, and if they are passing in a string it should be to_ied                        
    if self.belong_to_ids.include? key and not( value.nil? or ( value.respond_to? :empty? and value.empty? ) )
      return value.to_i
    end
    value
  end
  
  #TODO Consolidate this with call_setter
  #Called by overriden load
  def call_attribute_setter( key, value )
    #TODO If there is a setter, we shouldn't directly set the attribute hash - we should rely on the setter method
    # => Now, we are doing both
    setter_method_name = "#{key}="
    self.send( setter_method_name, @attributes[key.to_s] ) if self.respond_to? setter_method_name
  end    
  
  def self.find_by( all, field, *args )
    find( all.nil? ? :first : :all, :params => { field => args[0] } )      
  end
    
  FINDER_REGEXP = /^find_(?:(all)_?)?by_([a-zA-Z0-9_]+)$/ 

  def self.method_missing( symbol, *args )
    if symbol.to_s =~ FINDER_REGEXP 
      all, field_name = symbol.to_s.scan(FINDER_REGEXP).first #The ^ and $ mean only one thing will ever match this expression so use the first
      find_by( all, field_name, *args )        
    else
      super
    end
  end    
end