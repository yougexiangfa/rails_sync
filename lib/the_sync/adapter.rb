module TheSync
  class Adapter
    extend ActiveRecord::ConnectionHandling
    mattr_accessor :connection_handler, instance_writer: false
    self.connection_handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new

    def initialize(spec, options = {})
      @adapter_options = TheSync.options.fetch(spec, {})
      @adapter_options[:name] = spec
      @client = self.class.connection_handler.establish_connection(@adapter_options)
      puts "established connection: #{@client}"
    end

    def retrieve_connection
      self.class.connection_handler.retrieve_connection(@adapter_options[:name])
    end

    def server_id
      begin
        result = connection.query('select @@server_uuid')
      rescue
        result = connection.query('select @@server_id')
      end
      _id = result.to_a.flatten.first
      if _id.is_a?(Hash)
        _id.values.first
      else
        _id
      end
    end

    def connection
      retrieve_connection
    end

  end
end
