module Parsistence
  module Model
    attr_accessor :AVObject, :errors
    
    RESERVED_KEYS = [:objectId]

    def initialize(av=nil)
      if av
        self.AVObject = av
      else
        self.AVObject = AVObject.objectWithClassName(self.class.to_s)
      end

      self
    end
    
    def method_missing(method, *args, &block)
      method = method.to_sym
      setter = false
      
      if setter?(method)
        setter = true
        method = method.split("=")[0].to_sym
      end

      # Setters
      if RESERVED_KEYS.include?(method) && setter
        return self.AVObject.send("#{method}=", args)
      elsif relations.include?(method) && setter
        return setRelation(method, args.first)
      elsif fields.include?(method) && setter
        return setField(method, args.first)
      # Getters
      elsif RESERVED_KEYS.include?(method)
        return self.AVObject.send(method)
      elsif relations.include? method
        return getRelation(method)
      elsif fields.include? method
        return getField(method)
      elsif self.AVObject.respond_to?("#{method}=")
        return self.AVObject.send("#{method}=", *args, &block)
      elsif self.AVObject.respond_to?(method)
        return self.AVObject.send(method, *args, &block)
      else
        super
      end
    end

    def getter?(method)
      !setter?(method)
    end

    def setter?(method)
      method.to_s.include?("=")
    end

    # Override of ruby's respond_to?
    # 
    # @param [Symbol] method
    # @return [Bool] true/false
    def respond_to?(method)
      if setter?(method)
        method = method.to_s.split("=")[0]
      end

      method = method.to_sym unless method.is_a? Symbol

      return true if fields.include?(method) || relations.include?(method)

      super
    end 

    def fields
      self.class.send(:get_fields)
    end

    def relations
      self.class.send(:get_relations)
    end

    def getField(field)
      field = field.to_sym
      return @AVObject.send(field) if RESERVED_KEYS.include?(field)
      return @AVObject[field] if fields.include? field
      raise "Parsistence Exception: Invalid field name #{field} for object #{self.class.to_s}"
    end

    def setField(field, value)
      if RESERVED_KEYS.include?(field) || fields.include?(field.to_sym)
        return @AVObject.removeObjectForKey(field.to_s) if value.nil?
        return @AVObject.send("#{field}=", value) if RESERVED_KEYS.include?(field)
        return @AVObject[field] = value
      else
        raise "Parsistence Exception: Invalid field name #{field} for object #{self.class.to_s}"
      end
    end

    def getRelation(field)
      if has_many.include?(field.to_sym)
        relation = @AVObject.objectForKey(field) if relations.include? field.to_sym
        # This is not implemented yet
        # return @relation[field] ||= begin
        #   r = Relation.new(relation)
        #   r.klass = self
        #   r.belongs_to = true
        #   r
        # end
        raise "Parsistence Exception: has_many relationships aren't implemented yet. Use a regular query instead."
      elsif belongs_to.include?(field.to_sym)
        return self.getField(field)
      else
        raise "Parsistence Exception: Invalid relation name #{field} for object #{self.class.to_s}"
      end
    end

    def setRelation(field, value)
      value = value.AVObject if value.respond_to? :AVObject # unwrap object
      if has_many.include?(field.to_sym)
        relation = @AVObject.relationforKey(field)
        if value.nil?
          # Can't do it
          raise "Can't set nil for has_many relation."
        else
          return relation.addObject(value) if relations.include? field.to_sym
        end
      elsif belongs_to.include?(field.to_sym)
        return setField(field, value)
      end
      
      raise "Parsistence Exception: Invalid relation name #{field} for object #{self.class.to_s}"
    end

    # Returns all of the attributes of the Model
    # 
    # @return [Hash] attributes of Model
    def attributes
      attributes = {}
      fields.each do |f|
        attributes[f] = getField(f)
      end
      @attributes = attributes
    end

    # Sets the attributes of the Model
    # 
    # @param [Hash] attrs to set on the Model
    # @return [Hash] that you gave it
    # @note will throw an error if a key is invalid
    def attributes=(attrs)
      attrs.each do |k, v|
        if v.respond_to?(:each) && !v.is_a?(AVObject)
          self.attributes = v
        elsif self.respond_to? "#{k}="
          self.send("#{k}=", v) 
        else
          setField(k, v) unless k.nil?
        end
      end
    end

    # Save the current state of the Model to Parse
    #
    # @note calls before/after_save hooks
    # @note before_save MUST return true, or save will not be called on AVObject
    # @note does not save if validations fail
    # 
    # @return [Bool] true/false
    def save
      saved = false
      unless before_save == false
        self.validate

        if @errors && @errors.length > 0
          saved = false
        else
          saved = @AVObject.save
        end

        after_save if saved
      end
      saved
    end
    def before_save; end
    def after_save; end

    def validate
      reset_errors
      self.attributes.each do |field, value|
        validateField field, value
      end
    end

    # Checks to see if the current Model has errors
    #
    # @return [Bool] true/false
    def is_valid?
      self.validate
      return false if @errors && @errors.length > 0
      true
    end

    def delete
      deleted = false
      unless before_delete == false
        deleted = @AVObject.delete
      end
      after_delete if deleted
      deleted
    end
    def before_delete; end
    def after_delete; end


    # Validations
    def presenceValidations
      self.class.send(:get_presence_validations)
    end

    def presenceValidationMessages
      self.class.send(:get_presence_validation_messages)
    end

    def has_many
      self.class.send(:get_has_many)
    end

    def belongs_to
      self.class.send(:get_belongs_to)
    end

    def validateField(field, value)
      @errors ||= {}
      if presenceValidations.include?(field) && (value.nil? || value == "")
        messages = presenceValidationMessages
        if messages.include?(field) 
          @errors[field] = messages[field]
        else
          @errors[field] = "#{field} can't be blank" 
        end
      end
    end

    def errorForField(field)
      @errors[field] || false
    end

    def errors
      @errors
    end

    def valid?
      self.errors.nil? || self.errors.length == 0
    end

    def invalid?
      !self.valid?
    end

    def reset_errors
      @errors = nil
    end

    module ClassMethods
      
      # set the fields for the current Model
      #   used in method_missing
      #
      # @param [Symbol] args one or more fields
      def fields(*args)
        args.each {|arg| field(arg)}
      end
    
      # set a field for the current Model
      #
      # @param [Symbol] name of field
      # (see #fields)
      def field(name)
        @fields ||= [:objectId]
        @fields << name.to_sym
        @fields.uniq!
      end
      
      def get_fields
        @fields ||= []
      end

      # set the relations for the current Model
      #   used in method_missing
      #
      # @param [Symbol] args one or more relations
      def relations(*args)
        args.each { |arg| relation(arg)}
      end

      # set a relation for the current Model
      #
      # @param [Symbol] name of relation
      # (see #relations)
      def relation(name)
        @relations ||= []
        @relations << name.to_sym
        @relations.uniq!
      end

      def get_relations
        @relations ||= []
      end

      def has_many(field, args={})
        relation(field)

        @has_many ||= []
        @has_many << field
        @has_many.uniq!

        @has_many_attributes ||= {}
        @has_many_attributes[field] = args
      end

      def get_has_many
        @has_many ||= []
      end

      def belongs_to(field, args={})
        relation(field)

        @belongs_to ||= []
        @belongs_to << field
        @belongs_to.uniq!

        @belongs_to_attributes ||= {}
        @belongs_to_attributes[field] = args
      end

      def get_belongs_to
        @belongs_to ||= []
      end

      def get_belongs_to_attributes(field)
        @belongs_to_attributes[field] ||= { class_name: field }
      end

      # require a certain field to be present (not nil And not an empty String)
      # 
      # @param [Symbol, Hash] field and options (now only has message)
      def validates_presence_of(field, opts={})
        @presenceValidationMessages ||= {}
        @presenceValidationMessages[field] = opts[:message] if opts[:message]
        validate_presence(field)
      end

      def get_presence_validations
        @presenceValidations ||= {}
      end
      
      def get_presence_validation_messages
        @presenceValidationMessages ||= {}
      end

      def validate_presence(field)
        @presenceValidations ||= []
        @presenceValidations << field
      end
   end
    
    def self.included(base)
      base.extend(ClassMethods)
    end

  end
end
