# frozen_string_literal: true

class Group < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :billable_metric, -> { with_discarded }
  belongs_to :parent, -> { with_discarded }, class_name: 'Group', foreign_key: 'parent_group_id', optional: true
  has_many :children, class_name: 'Group', foreign_key: 'parent_group_id'
  has_many :properties, class_name: 'GroupProperty'
  has_many :fees

  validates :key, :value, presence: true

  default_scope -> { kept }
  scope :parents, -> { where(parent_group_id: nil) }
  scope :children, -> { where.not(parent_group_id: nil) }

  def name
    parent ? "#{parent.value} • #{value}" : value
  end
end
