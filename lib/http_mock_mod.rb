require 'active_resource/connection'

module ActiveResource
  class InvalidRequestError < StandardError; end #:nodoc:

  class HttpMock
    class ResponderWithLoc < Responder
      for method in [ :post ]
        module_eval <<-EOE
          def #{method}(path, request_headers = {}, body = nil, status = 200, response_headers = {}, response_body = nil, location = nil)
            @responses[Request.new(:#{method}, path, nil, request_headers)] = ResponseWithLoc.new(response_body || body || "", status, response_headers, location)
          end
        EOE
      end
    end
     
    class << self
      def respond_to_with_location(pairs = {})
        reset!
        pairs.each do |(path, response)|
          responses[path] = response
        end

        if block_given?
          yield ResponderWithLoc.new(responses)
        else
          ResponderWithLoc.new(responses)
        end
      end
    end
    
    for method in [ :post, :put ] # try to remove the authorization info from @request.headers
      module_eval <<-EOE
        def #{method}(path, body, headers)  
          request = ActiveResource::Request.new(:#{method}, path, body, headers)
          request.headers.delete('Authorization')
          self.class.requests << request
          self.class.responses[request] || raise(InvalidRequestError.new("No response recorded for: \#{request.inspect}"))
        end
      EOE
    end      
    
    for method in [ :get, :delete ]
      module_eval <<-EOE
        def #{method}(path, headers)
          request = ActiveResource::Request.new(:#{method}, path, nil, headers)
          request.headers.delete('Authorization')
          self.class.requests << request
          self.class.responses[request] || raise(InvalidRequestError.new("No response recorded for: \#{request.inspect}"))
        end
      EOE
    end
    
  end

  class ResponseWithLoc < Response
    attr_accessor :location

    def initialize(body, message = 200, headers = {}, location=nil)
      @body, @message, @headers = body, message.to_s, headers
      @code = @message[0,3].to_i 
      self['Location'] = location if location

      resp_cls = Net::HTTPResponse::CODE_TO_OBJ[@code.to_s]
      if resp_cls && !resp_cls.body_permitted?
        @body = nil
      end

      if @body.nil?
        self['Content-Length'] = "0"
      else
        self['Content-Length'] = body.size.to_s
      end
    end
  end
end
