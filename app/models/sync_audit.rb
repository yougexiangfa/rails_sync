class SyncAudit < ApplicationRecord
  serialize :audited_changes, Hash

  enum state: {
    init: 'init',
    applied: 'applied',
    finished: 'finished'
  }

  enum operation: {
    update: 'update',
    delete: 'delete',
    insert: 'insert'
  }, _prefix: true

  belongs_to :synchro, polymorphic: true, optional: true
  belongs_to :operator, polymorphic: true, optional: true

  scope :for_callback, -> { where(state: :applied) }

  after_initialize if: :new_record? do
    self.state = 'init'
  end

  def apply_changes
    if self.operation_update? && self.synchro
      self.synchro.assign_attributes to_apply_params
      self.class.transaction do
        self.synchro.save!
        self.update! state: 'applied'
      end
    elsif self.operation_delete? && self.synchro
      self.class.transaction do
        self.synchro.destroy!
        self.update! state: 'applied'
      end
    elsif self.operation_insert?
      synchro_model = self.synchro_type.constantize
      _synchro = synchro_model.find_or_initialize_by(self.synchro_primary_key => self.synchro_id)
      _synchro.assign_attributes to_apply_params
      self.class.transaction do
        _synchro.save!
        self.update! synchro_id: _synchro.id, state: 'applied'
      end
    end
  end

  def apply_callback
    SyncAudit.for_callback.each do |sync|
      sync.synchro.respond_to?(:after_sync) && sync.synchro.after_sync
    end
  end

  def to_apply_params
    audited_changes.transform_values do |v|
      v[1]
    end
  end

  def self.synchro_types
    SyncAudit.select(:synchro_type).distinct.pluck(:synchro_type).compact
  end

  def self.synchro_apply(type, operation: ['update', 'delete', 'insert'])
    SyncAudit.where(state: 'init', synchro_type: type, operation: operation).find_each do |sync_audit|
      begin
        sync_audit.apply_changes
      rescue SystemStackError, ActiveRecordError => e
        logger.warn e.message
      end
    end
  end

end
