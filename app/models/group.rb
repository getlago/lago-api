# frozen_string_literal: true

class Group < ApplicationRecord
  belongs_to :billable_metric
  belongs_to :parent, class_name: 'Group', foreign_key: 'parent_group_id', optional: true
  has_many :children, class_name: 'Group', foreign_key: 'parent_group_id'
  has_many :properties, class_name: 'GroupProperty'
  has_many :fees

  STATUS = %i[active inactive].freeze
  enum status: STATUS

  validates :key, :value, presence: true

  scope :parents, -> { where(parent_group_id: nil) }
  scope :children, -> { where.not(parent_group_id: nil) }
end
