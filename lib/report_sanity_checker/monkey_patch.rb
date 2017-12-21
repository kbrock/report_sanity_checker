# monkey patch required for earlier versions
if !MiqReport.method_defined?(:menu_name=)
  class MiqReport
    alias_attribute :menu_name, :name
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
