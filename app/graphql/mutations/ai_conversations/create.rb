# frozen_string_literal: true

module Mutations
  module AiConversations
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "ai_conversations:create"

      graphql_name "CreateAiConversation"
      description "Creates a new AI conversation"

      argument :input_data, String, required: true

      type Types::AiConversations::Object

      def resolve(input_data:)
        ai_conversation = current_organization.ai_conversations.create!(
          conversation_id: SecureRandom.uuid,
          membership: current_organization.memberships.find_by(user_id: context[:current_user].id),
          input_data: "Content: "
        )

        Thread.new do
          uri = URI("https://api.mistral.ai/v1/conversations")

          req = Net::HTTP::Post.new(uri)
          # req["Authorization"] = "Bearer #{ENV["MISTRAL_API_KEY"]}"
          req["Authorization"] = "Bearer 7VZPtWSFvS1PHTMbpn1nCiHkQfqtVX75"
          req["Content-Type"] = "application/json"
          req.body = {
            agent_id: "ag:60070909:20250806:lago-billing-assistant:56aead9d",
            inputs: "input_data",
            stream: true
          }.to_json


          Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
            http.request(req) do |response|
              buffer = ""

              response.read_body do |chunk|
                buffer = buffer.dup
                buffer << chunk

                buffer.lines.each do |line|
                  puts "--------------------------------"
                  puts "Line: #{line.inspect}"
                  puts "--------------------------------"

                  #next unless line.start_with?("data:")
                  #data = line.sub("data:", "").strip
                  #next if data == "[DONE]"

                  #parsed = JSON.parse(data) rescue nil
                  #content = parsed.dig("choices", 0, "delta", "content")
                  #next unless content

                  # Append au champ input_data (ou réponse)
                  #ai_conversation.input_data += content
                  ai_conversation.input_data += line
                  #ai_conversation.updated_at = Time.now

                  # ⚠️ si tu ne persistes pas, skip la ligne ci-dessous
                  ai_conversation.save!

                  # Emit l’objet complet à chaque message partiel
                  puts "--------------------------------"
                  puts "Emitting ai_conversation_streamed: #{ai_conversation.inspect}"
                  puts "--------------------------------"
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

        ai_conversation
      end
    end
  end
end