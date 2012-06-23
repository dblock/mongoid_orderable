module Mongoid::Orderable
  extend ActiveSupport::Concern

  module ClassMethods
    def orderable options = {}
      configuration = {
        :column => :position,
        :index => true,
        :scope => nil
      }

      configuration.merge! options if options.is_a?(Hash)
      configuration[:scope] = "#{configuration[:scope]}_id".to_sym if configuration[:scope].is_a?(Symbol) && configuration[:scope].to_s !~ /_id$/

      field configuration[:column], :type => Integer
      if configuration[:index]
        if MongoidOrderable.mongoid2?
          index configuration[:column]
        else
          index(configuration[:column] => 1)
        end
      end

      case configuration[:scope]
      when Symbol then
        scope :orderable_scope, lambda { |document|
          where(configuration[:scope] => document.send(configuration[:scope])) }
      when Proc then
        scope :orderable_scope, configuration[:scope]
      else
        scope :orderable_scope, lambda { |document| where({}) }
      end

      define_method :orderable_column do
        configuration[:column]
      end

      before_save :add_to_list
      after_destroy :remove_from_list
    end
  end

  def move_to! target_position
    @move_to = target_position
    save
  end
  alias_method :insert_at!, :move_to!

  def move_to target_position
    @move_to = target_position
  end
  alias_method :insert_at, :move_to

  def move_to= target_position
    @move_to = target_position
  end
  alias_method :insert_at=, :move_to=

  [:top, :bottom].each do |symbol|
    define_method "move_to_#{symbol}" do
      move_to symbol
    end

    define_method "move_to_#{symbol}!" do
      move_to! symbol
    end
  end

  [:higher, :lower].each do |symbol|
    define_method "move_#{symbol}" do
      move_to symbol
    end

    define_method "move_#{symbol}!" do
      move_to! symbol
    end
  end

  def first?
    in_list? && orderable_position == 1
  end

  def last?
    in_list? && orderable_position == bottom_orderable_position
  end

  def in_list?
    !orderable_position.nil?
  end

  def add_to_list
    apply_position @move_to
  end

  def remove_from_list
    orderable_scoped.where(orderable_column.gt => orderable_position).inc(orderable_column, -1)
  end

private

  def orderable_position
    send orderable_column
  end

  def orderable_position= value
    send "#{orderable_column}=", value
  end

  def orderable_scoped
    if embedded?
      send(metadata.inverse).send(metadata.name).orderable_scope(self)
    else
      self.class.orderable_scope(self)
    end
  end

  def orderable_scope_changed?
    !orderable_scoped.where(:_id => _id).exists?
  end

  def apply_position target_position
    if persisted? && !embedded? && orderable_scope_changed?
      self.class.unscoped.find(_id).remove_from_list
      self.orderable_position = nil
    end

    return if !target_position && in_list?

    target_position = target_position_to_position target_position

    unless in_list?
      orderable_scoped.where(orderable_column.gte => target_position).inc(orderable_column, 1)
    else
      orderable_scoped.where(orderable_column.gte => target_position, orderable_column.lt => orderable_position).inc(orderable_column, 1) if target_position < orderable_position
      orderable_scoped.where(orderable_column.gt => orderable_position, orderable_column.lte => target_position).inc(orderable_column, -1) if target_position > orderable_position
    end

    self.orderable_position = target_position
  end

  def target_position_to_position target_position
    target_position = :bottom unless target_position

    target_position = case target_position.to_sym
      when :top then 1
      when :bottom then bottom_orderable_position
      when :higher then orderable_position.pred
      when :lower then orderable_position.next
    end unless target_position.is_a? Numeric

    target_position = 1 if target_position < 1
    target_position = bottom_orderable_position if target_position > bottom_orderable_position
    target_position
  end

  def bottom_orderable_position
    @bottom_orderable_position = begin
      max = orderable_scoped.distinct(orderable_column).map(&:to_i).max.to_i
      in_list? ? max : max.next
    end
  end

end