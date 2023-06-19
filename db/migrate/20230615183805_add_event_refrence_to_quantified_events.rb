# frozen_string_literal: true

class AddEventRefrenceToQuantifiedEvents < ActiveRecord::Migration[7.0]
  def change
    add_reference :quantified_events, :event, type: :uuid, index: true
  end
end
