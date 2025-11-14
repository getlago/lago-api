# frozen_string_literal: true

module LagoMcpClient
  class SseClient
    def initialize(url:, session_id:)
      @uri = URI(url)
      @session_id = session_id
      @running = false
      @mutex = Mutex.new
      @thread = nil
      @callbacks = []
    end

    def start(&block)
      @mutex.synchronize { @callbacks << block if block }
      @running = true
      @thread ||= Thread.new { run }
    end

    def stop
      @running = false
      @thread&.join(1)
      @thread = nil
    end

    private

    def run
      Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == "https") do |http|
        request = Net::HTTP::Get.new(@uri)
        request["Mcp-Session-Id"] = @session_id
        request["Accept"] = "application/json,text/event-stream"
        request["Cache-Control"] = "no-cache"

        http.request(request) do |response|
          next unless response.code == "200"
          Rails.logger.info("SSE connection successful")
          response.read_body do |chunk|
            break unless @running
            chunk.split("\n").each do |line|
              next if line.strip.empty?
              if line.start_with?("data: ")
                event_data = JSON.parse(line[6..-1]) rescue line[6..-1]
                @callbacks.each { |cb| cb&.call(event_data) }
              end
            end
          end
        end
      end
    rescue Interrupt
    rescue
    end
  end
end
