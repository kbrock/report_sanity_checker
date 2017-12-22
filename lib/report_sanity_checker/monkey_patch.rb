# monkey patch required for earlier versions
if !MiqReport.method_defined?(:menu_name=)
  class MiqReport
    alias_attribute :menu_name, :name
  end
end

if !MiqReport.method_defined?(:include_as_hash)
  class MiqReport
    def include_as_hash(includes = include, klass = db_class, klass_cols = cols)
      result = {}
      if klass_cols && klass && klass.respond_to?(:virtual_attribute?)
        klass_cols.each do |c|
          result[c.to_sym] = {} if klass.virtual_attribute?(c) && !klass.attribute_supported_by_sql?(c)
        end
      end

      if includes.kind_of?(Hash)
        includes.each do |k, v|
          k = k.to_sym
          if k == :managed
            result[:tags] = {}
          else
            assoc_reflection = klass.reflect_on_association(k)
            assoc_klass = (assoc_reflection.options[:polymorphic] ? k : assoc_reflection.klass) if assoc_reflection

            result[k] = include_as_hash(v && v["include"], assoc_klass, v && v["columns"])
          end
        end
      elsif includes.kind_of?(Array)
        includes.each { |i| result[i.to_sym] = {} }
      end

      result
    end
  end

  def invent_includes
    return {} unless col_order
    col_order.each_with_object({}) do |col, ret|
      next unless col.include?(".")
      *rels, _col = col.split(".")
      rels.inject(ret) { |h, rel| h[rel.to_sym] ||= {} } unless col =~ /managed\./
    end
  end
end

#if !MiqExpression.method_defined?(:fields)
MiqExpression
class MiqExpression
  def fields(expression = exp)
    case expression
    when Array
      expression.flat_map { |x| fields(x) }
    when Hash
      return [] if expression.empty?

      if (val = expression["field"] || expression["count"] || expression[""])
        ret = []
        v = self.class.parse_field_or_tag(val)
        ret << v if v
        v = self.class.parse_field_or_tag(expression["value"].to_s)
        ret << v if v
        ret
      else
        fields(expression.values)
      end
    end
  end
end
#end

if !MiqExpression::Field.method_defined?(:virtual_reflection?)
  class MiqExpression::Field
    def virtual_attribute?
      target.virtual_attribute?(column)
    end

    def virtual_reflection?
      associations.present? && (model.follow_associations_with_virtual(associations) != model.follow_associations(associations))
    end
    # old version doesn't include virtual_reflection?
    def attribute_supported_by_sql?
      !custom_attribute_column? && target.attribute_supported_by_sql?(column) && !virtual_reflection?
    end

    def collect_reflections
      klass = model
      associations.collect do |name|
        reflection = klass.reflect_on_association(name)
        if reflection.nil?
          if klass.reflection_with_virtual(name)
            break
          else
            raise ArgumentError, "One or more associations are invalid: #{association_names.join(", ")}"
          end
        end
        klass = reflection.klass
        reflection
      end
    end

    def collect_reflections_with_virtual(association_names)
      klass = model
      associations.collect do |name|
        reflection = klass.reflection_with_virtual(name) ||
                     raise(ArgumentError, "One or more associations are invalid: #{associations.join(", ")}")
        klass = reflection.klass
        reflection
      end
    end
  end
end
