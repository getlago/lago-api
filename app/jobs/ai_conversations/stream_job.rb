# frozen_string_literal: true

module AiConversations
  class StreamJob < ApplicationJob
    queue_as :low_priority

    def perform(id)
      ai_conversation = AiConversation.find(id)
  
      uri = URI("https://api.mistral.ai/v1/conversations")
      req = Net::HTTP::Post.new(uri)
      # req["Authorization"] = "Bearer #{ENV.fetch("MISTRAL_API_KEY")}"
      req["Authorization"] = "Bearer 7VZPtWSFvS1PHTMbpn1nCiHkQfqtVX75"

      req["Content-Type"] = "application/json"
      req.body = {
        agent_id: "ag:60070909:20250806:lago-billing-assistant:56aead9d",
        inputs: "Who is Albert Einstein?",
        stream: true
      }.to_json
  
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req) do |response|
          response.read_body do |chunk|
            chunk.each_line do |line|
              next unless line.start_with?("data:")
      
              data = line.sub("data:", "").strip
              event = JSON.parse(data) rescue nil

              if event && event["type"] == "conversation.response.done"
                ai_conversation.update!(status: "completed")
                break 
              end

              if event && event["content"]
                puts "--------------------------------"
                puts "event content: #{event["content"]}"
                puts "--------------------------------"
                # puts event["content"] # streaming piece by piece

                ai_conversation.input_data = (ai_conversation.input_data || "").dup + event["content"]

                ai_conversation.save!
    
                LagoApiSchema.subscriptions.trigger(
                  :ai_conversation_streamed,
                  { conversation_id: ai_conversation.conversation_id },
                  ai_conversation
                )
              end
            end
          end
        end
      end
    end
  end
end
