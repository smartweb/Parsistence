module Parsistence
  module User
    include Parsistence::Model

    attr_accessor :AVUser
    
    RESERVED_KEYS = [:objectId, :username, :password, :email]

    def initialize(pf=nil)
      if pf
        self.AVObject = pf
      else
        self.AVObject = AVUser.new
      end

      self
    end
    
    def AVObject=(value)
      @AVObject = value
      @AVUser = @AVObject
    end
    
    def AVUser=(value)
      self.AVObject = value
    end

    def password=(value)
      self.AVUser.password = value
    end

    def signUp
      saved = false
      unless before_save == false
        self.validate

        if @errors && @errors.length > 0
          saved = false
        else
          saved = @AVObject.signUp
        end

        after_save if saved
      end
      saved
    end

    module ClassMethods
      include Parsistence::Model::ClassMethods

      def all
        query = AVQuery.queryForUser
        users = query.findObjects
        users
      end
      
      def currentUser
        return AVUser.currentUser if AVUser.currentUser
        nil
      end

      def current_user
        if AVUser.currentUser
          return @current_user ||= self.new(AVUser.currentUser)
        end
        nil
      end

      def log_out
        @current_user = nil
        AVUser.logOut
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end
  end
end
