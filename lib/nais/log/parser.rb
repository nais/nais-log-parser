# coding: utf-8
require "nais/log/parser/version"
require "time"

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

      def Parser.remap_elasticsearch_fields(time, record)
        record["received_at"] = Time.new.iso8601(9)
        if !record.has_key?("@timestamp")
          record["@timestamp"] = record.delete("timestamp") || record.delete("time") || Time.at(time).iso8601(9)
        end
        record["message"] = record.delete("log") unless record.has_key?("message")
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
          if k =~ /^(?:@timestamp|@version|type|received_at|message|container|host|namespace|application|pod|thread|component|category|level|stack_trace|exception|cluster|envclass|content_length|remote_ip|response_code|user|ident|processing_time|source)$/
            r[k] = record[k]
          else
            r["x_"+k] = record[k]
          end
        }
        r
      end

      def Parser.parse_accesslog(str)
        if m = str.match(/^(\S+) +(?:(\S+) )?(\S+) \[([^\]]+)\] \"([^\"]*)\" (\S+) (\S+)(.*)/)
          r = {}
          r['remote_ip'] = m[1]
          r['ident'] = m[2] unless (m[2].nil? || m[2] == '-')
          r['user'] = m[3] unless m[3] == '-'
          r['timestamp'] = Time.strptime(m[4], "%d/%b/%Y:%H:%M:%S %Z").iso8601
          r['request'] = m[5]
          r['response_code'] = m[6] unless m[6] == '-'
          r['content_length'] = m[7] unless m[7] == '-'
          ext = m[8] unless m[8] == ''
          return r, ext
        else
          return nil
        end
      end

      def Parser.parse_accesslog_with_processing_time(str)
        r,ext = Parser.parse_accesslog(str)
        if !ext.nil? && m = ext.match(/^\s+(?:\"?-\"?|([0-9.]+)(?:[µm]?s))?$/u)
          r['processing_time'] = m[1] unless m[1].nil?
        end
        return r
      end

      def Parser.parse_glog(str)
        if m = str.match(/^([IWEF])(\d{4} \d\d:\d\d:\d\d.\d{6})\s+(\S+)\s([^:]+):(\d+)\]\s+(.*)/)
          r = {}
          r['level'] = case m[1]
                       when 'I'
                         'Info'
                       when 'W'
                         'Warning'
                       when 'E'
                         'Error'
                       when 'F'
                         'Fatal'
                       end
          r['timestamp'] = Time.strptime(m[2], "%m%d %H:%M:%S.%N").iso8601(9)
          r['thread'] = m[3]
          r['file'] = m[4]
          r['line'] = m[5]
          r['message'] = m[6]
          return r
        else
          return nil
        end
      end
      
    end
  end
end
