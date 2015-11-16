require 'yaml'
require 'rest-client'
require 'time'

module Localeapp
  class Poller
    include ::Localeapp::ApiCall

    # when we last asked the service for updates
    attr_accessor :polled_at

    # the last time the service had updates for us
    attr_accessor :updated_at

    def initialize
      @sync_file  = SyncFile.new( Localeapp.configuration.synchronization_data_file )
      @polled_at  = sync_data.polled_at
      @updated_at = sync_data.updated_at
    end

    def sync_data
      sync_file.refresh
      sync_file.data
    end

    def write_synchronization_data!(polled_at, updated_at)
      sync_file.write(polled_at, updated_at)
    end

    def needs_polling?
      sync_data.polled_at < (Time.now.to_i - Localeapp.configuration.poll_interval)
    end

    def needs_reloading?
      sync_data.updated_at != @updated_at
    end

    def poll!
      api_call :translations,
        :url_options => { :query => { :updated_at => updated_at }},
        :success => :handle_success,
        :failure => :handle_failure,
        :max_connection_attempts => 1
      @success
    end

    def handle_success(response)
      Localeapp.log_with_time "poll success"
      @success = true
      Localeapp.updater.update(Localeapp.load_yaml(response))
      write_synchronization_data!(current_time, Time.parse(response.headers[:date]))
      # Jeff added this below to make sure we update the updated_at since this line was in the controller code that we aren't' using now
      ::Localeapp.poller.updated_at = ::Localeapp.poller.sync_data.updated_at
    end

    def handle_failure(response)
      if response.code == 304
        Localeapp.log_with_time "No new data"
        # Nothing new, update synchronization files
        write_synchronization_data!(current_time, updated_at)
      end
      @success = false
    end

  private

    # a SyncFile object representing the synchronization file
    attr_reader :sync_file

    def current_time
      Time.now
    end
  end
end
