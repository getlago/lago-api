# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::GraphqlSubscriptions::AiConversation do
  subject { described_class }

  it do
    

    RSpec.describe 'AiConversation Subscription', type: :subscription do
      let(:conversation_id) { SecureRandom.uuid }
    
      let!(:ai_conversation) do
        AiConversation.create!(
          conversation_id: conversation_id,
          input_data: 'Initial',
          organization: create(:organization) # assuming you have a factory
        )
      end
    
      let(:query) do
        <<~GRAPHQL
          subscription($conversationId: ID!) {
            aiConversationStreamed(conversationId: $conversationId) {
              id
              inputData
              conversationId
            }
          }
        GRAPHQL
      end
    
      it 'receives updates when triggered' do
        # Subscribe
        response = nil
        execute_subscription(
          query: query,
          variables: { conversationId: conversation_id }
        ) do |result|
          response = result
        end
    
        # Simulate an update
        ai_conversation.update!(input_data: 'New streamed content')
    
        LagoApiSchema.subscriptions.trigger(
          :ai_conversation_streamed,
          { conversation_id: conversation_id },
          ai_conversation
        )
    
        # Assert
        expect(response.dig('data', 'aiConversationStreamed')).to include(
          'conversationId' => conversation_id,
          'inputData' => 'New streamed content'
        )
      end
    end
    