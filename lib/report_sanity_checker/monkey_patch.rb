# this should come into play in Spasky
if !MiqExpression::Field.method_defined?(:virtual_reflection?)
  class MiqExpression::Target
    # @return true if column is a database column
    def db_column?
      target.has_attribute?(column) ||
        target.try(:attribute_alias?, column)
    end
  end
  class MiqExpression::Field
    # TODO: add to MiqExpression::Field
    def virtual_reflection?
      associations.present? && (model.follow_associations_with_virtual(associations) != model.follow_associations(associations))
    rescue ArgumentError
      # polymorphic is throwing us
      # assume the worst
      true
    end
  end
end

# Add methods to MiqReport to support report_sanity_checker
class MiqReport
  # Get condition columns from report conditions
  def condition_columns
    if (miq_cols = conditions.try(:fields))
      # use fully qualified field names
      Set.new(miq_cols.map { |c| ((c.associations||[]) + [c.column]).compact.join(".") })
    else
      Set.new
    end
  end

  # Get display filter columns from report display_filter
  def display_filter_columns
    if (miq_cols = display_filter.try(:fields))
      # use fully qualified field names
      Set.new(miq_cols.map { |c| ((c.associations||[]) + [c.column]).compact.join(".") })
    else
      Set.new
    end
  end

  # Convert MiqExpression::Field objects to strings
  def flds_to_strs(flds)
    flds.map { |f| (f.associations + [f.column]).join(".") }
  end

  # Convert "includes" recursive hash to columns
  # TODO: know when it is a virtual association
  def includes_to_cols(model, h, associations = [])
    return [] if h.blank?
    h.flat_map do |table, table_hash|
      next_associations = associations + [table]
      (table_hash["columns"] || []).map { |col| MiqExpression::Field.new(model, next_associations, col) } +
        includes_to_cols(model, table_hash["includes"], next_associations)
    end
  end

  # Get includes columns from report include
  def includes_columns
    Set.new(flds_to_strs(includes_to_cols(db, include)))
  end
end
