require "nais/log/parser/version"

module Nais
  module Log
    module Parser

      def Parser.flatten_hash(hash, path = "")
        hash.each_with_object({}) do |(k, v), ret|
          key = (path + k.to_s).tr('.','_')
          if v.is_a? Hash
            ret.merge! Parser.flatten_hash(v, key.to_s + "_")
          else
            ret[key] = v
          end
        end
      end

      def Parser.get_exceptions(str)
        exps = str.scan(/\b[A-Z]\w+Exception\b/)
        if exps.any?
          exps.uniq!
          exps.size == 1 ? exps.first : exps
        end
      end

      def Parser.remap_kubernetes_fields(record)
        record["category"] = record.delete("stream") if record.has_key?("stream")
        if record["docker"].is_a?(Hash)
          record["container"] = record["docker"]["container_id"]
          record.delete("docker")
        end
        if record["kubernetes"].is_a?(Hash)
          record["host"] = record["kubernetes"]["host"]
          record["namespace"] = record["kubernetes"]["namespace_name"]
          record["application"] = record["kubernetes"]["container_name"]
          record["pod"] = record["kubernetes"]["pod_name"]
          record.delete("kubernetes")
        end
        record
      end

      def Parser.remap_elasticsearch_fields(record)
        record["received_at"] = Time.new.iso8601(9)
        if !record.has_key?("@timestamp")
          record["@timestamp"] = record.delete("timestamp") if record.has_key?("timestamp")
          record["@timestamp"] = time.iso8601(9) unless record.has_key?("@timestamp")
        end
        record["message"] = new_record.delete("log") unless new_record.has_key?("message")
        record
      end

      def Parser.remap_java_fields(record)
        record["thread"] = record.delete("thread_name") if record.has_key?("thread_name")
        record["component"] = record.delete("logger_name") if record.has_key?("logger_name")
        record["level"].capitalize! if record.has_key?("level")
        record.delete("level_value")
        record
      end

      def Parser.prefix_nonstandard_fields(record)
        r = {}
        record.each{|k,v|
          if k =~ /^(?:@timestamp|@version|type|received_at|message|container|host|namespace|application|pod|thread|component|category|level|stack_trace|exception|cluster|envclass)$/
            r[k] = record[k]
          else
            r["x_"+k] = record[k]
          end
        }
        r
      end
      
    end
  end
end
