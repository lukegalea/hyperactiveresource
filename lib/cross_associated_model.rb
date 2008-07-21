module CrossAssociatedModel
  def self.included(mod)
    mod.extend(CrossAssociatedModelClassMethods)
  end
  
  module CrossAssociatedModelClassMethods    
    
    #The base implementation assumes a resource that references a record
    def belongs_to_record( name )
      #Assumes this record has a "name_id" and that a "Name" exists that is an active_record
      instance_var = "@#{name}"
      
      define_method( name ) do      
        association_id = send("#{name}_id")        
        resource_class = name.to_s.classify.constantize

        if association_id == 0 or association_id.nil?
          return nil
        elsif instance_variable_get(instance_var).nil?
          instance_variable_set( instance_var, resource_class.find(association_id) )
        end
        instance_variable_get(instance_var)
      end
      
      define_method( "#{name}=" ) do |new_associated_resource|        
        instance_variable_set( instance_var, new_associated_resource )
        send("#{name}_id=", (new_associated_resource.nil? ? nil : new_associated_resource.id))
      end
    end        
    
    #The base implementation assumes a resource that references many record
    def has_many_records( name )
      #Assumes this record has a "name_ids" and that a "Name" exists that is an active_record
      instance_var = "@#{name}"
      
      define_method( name ) do                    
        resource_class = name.to_s.classify.constantize
        finder_method = "find_all_by_#{self.class.name.tableize.singularize}_id"

        if instance_variable_get(instance_var).nil?
          instance_variable_set( instance_var, resource_class.send( finder_method, self.id ) )
        end
        instance_variable_get(instance_var)
      end            
    end
    
    alias_method :belongs_to_resource, :belongs_to_record    
    alias_method :has_many_resources, :has_many_records
  end
end