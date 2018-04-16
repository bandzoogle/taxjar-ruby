require 'addressable/uri'
require 'uri'
require 'net/http'
require 'net/https'

module Taxjar
  module API
    class Request
      DEFAULT_API_URL = 'https://api.taxjar.com'
      SANDBOX_API_URL = 'https://api.sandbox.taxjar.com'

      VERB_MAP = {
        :get    => Net::HTTP::Get,
        :patch => Net::HTTP::Patch,
        :post   => Net::HTTP::Post,
        :put    => Net::HTTP::Put,
        :delete => Net::HTTP::Delete
      }

      attr_reader :client, :uri, :headers, :request_method, :path, :object_key, :options

      # @param client [Taxjar::Client]
      # @param request_method [String, Symbol]
      # @param path [String]
      # @param object_key [String]
      def initialize(client, request_method, path, object_key, options = {})
        @client = client
        @request_method = request_method
        @path = path
        @base_url = client.api_url ? client.api_url : DEFAULT_API_URL
        @uri = Addressable::URI.parse(@base_url + path)
        set_request_headers(client.headers || {})
        @object_key = object_key
        @options = options
      end

      def perform
        uri = URI.parse(@uri.to_s)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true #@config.scheme == "https"

        if @options[:timeout].to_i > 0
          http.read_timeout = @options[:timeout]
          http.continue_timeout = @options[:timeout]
          http.open_timeout = @options[:timeout]
          http.ssl_timeout = @options[:timeout]
        end

        path = uri.path
        if @request_method  == :get && ! @options.empty?
          encoded = URI.encode_www_form(@options)
          path = [path, encoded].join("?")
        end

        request = VERB_MAP[@request_method].new(path)
        if @request_method != :get
          request.body = @options.to_json
        end

        headers.each { |k, v|
          request[k] = v
        }
        request[:host] = uri.host

        response = http.request(request)
        response_body = symbolize_keys!(JSON.parse(response.body))
        fail_or_return_response_body(response.code.to_i, response_body)
      end

      private

        def set_request_headers(custom_headers = {})
          @headers = {}
          @headers[:user_agent] = client.user_agent
          @headers[:authorization] = "Bearer #{client.api_key}"
          @headers[:connection] = 'close'
          @headers['Content-Type'] = 'application/json; charset=UTF-8'
          @headers.merge!(custom_headers)
        end

        def symbolize_keys!(object)
          if object.is_a?(Array)
            object.each_with_index do |val, index|
              object[index] = symbolize_keys!(val)
            end
          elsif object.is_a?(Hash)
            object.keys.each do |key|
              object[key.to_sym] = symbolize_keys!(object.delete(key))
            end
          end
          object
        end

        def fail_or_return_response_body(code, body)
          e = extract_error(code, body)
          fail(e) if e
          body[object_key.to_sym]
        end

        def extract_error(code, body)
          klass = Taxjar::Error::ERRORS[code]
          if !klass.nil?
            klass.from_response(body)
          end
        end
    end
  end
end
