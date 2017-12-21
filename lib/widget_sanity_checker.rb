class WidgetSanityChecker
  def filenames
    Dir.glob("product/dashboard/widgets/*")
  end

  def widget_and_report_names
    filenames.map do |filename|
      yaml = YAML.load(IO.read(filename))
      if yaml["resource_type"] != "MiqReport"
        puts "skipping #{filename}:: #{yaml["resource_type"]}"
        #next([])
        nil
      else
        resource_name = yaml["resource_name"]
        [filename, yaml, resource_name]
      end
    end.compact
  end

  def run
    checker = ReportSanityChecker.new
    widget_and_report_names.each do |widget, widget_yaml, rpt_name|
      # could have loaded the yaml file with the report name, but this is easier
      rpt = MiqReport.find_by(name: rpt_name)
      puts "", "# WIDGET: #{widget}"
# skipping timezone saves a lot of performance time
# options:
#   :timezone_matters: false
      puts "# TIMEZONE MATTERS: #{widget_yaml["options"][:timezone_matters]}" if widget_yaml["options"].try(:key?, :timezone_matters)
      puts "# REPORT: #{rpt_name}", ""
      if rpt
        checker.check_report(rpt)
      else
        puts "ERROR: Couldn't find #{rpt_name}"
      end
    end.size
  end

  def self.run(argv = ARGV)
    new.run
  end
end
