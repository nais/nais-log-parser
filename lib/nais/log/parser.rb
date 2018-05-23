# coding: utf-8
require "nais/log/parser/version"
require "time"
require "json"

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

      def Parser.get_keywords(str, regex)
        keywords = str.scan(regex)
        if keywords.any?
          keywords.uniq!
          keywords.size == 1 ? keywords.first : keywords
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

      def Parser.merge_json_field(record, field)
        if record.has_key?(field)
          value = record[field].strip
          if value[0].eql?('{') && value[-1].eql?('}')
            begin
              record = JSON.parse(value).merge(record)
              record.delete(field)
            rescue JSON::ParserError=>e
            end
          end
        end
        record
      end

      def Parser.remap_elasticsearch_fields(time, record)
        record["received_at"] = Time.new.iso8601(9)
        unless record.has_key?("@timestamp")
          record["@timestamp"] = record.delete("timestamp") || record.delete("time") || Time.at(time).iso8601(9)
        end
        unless record.has_key?("message")
          record["message"] = record.delete("msg") || record.delete("log")
        end
        record.delete('log')
        record
      end

      def Parser.remap_java_fields(record)
        record["thread"] = record.delete("thread_name") if record.has_key?("thread_name")
        record["component"] = record.delete("logger_name") if record.has_key?("logger_name")
        if record.has_key?("level")
          record["level"].capitalize!
          record['level'] = 'Warning' if record['level'] == 'Warn'
        end
        record.delete("level_value")
        record.delete("ndc")
        record.delete("source_host")
        if record.has_key?('exception')
          record['stack_trace'] = record['exception']['stacktrace'] if record['exception'].has_key?('stacktrace')
          record.delete('exception')
        end
        if record.has_key?('mdc')
          record['mdc'].each{|k,v|
            record[k] = record['mdc'][k]
          }
          record.delete('mdc')
        end
        record
      end

      # remap fields from https://github.com/inconshreveable/log15/
      def Parser.remap_log15(record)
        record['@timestamp'] = record.delete('t') if record.has_key?('t')
        record['message'] = record.delete('msg') if record.has_key?('msg')
        record['component'] = record.delete('logger') if record.has_key?('logger')
        if record.has_key?('lvl')
          record['level'] = case record['lvl']
                            when 'dbug'
                              'Debug'
                            when 'info'
                              'Info'
                            when 'warn'
                              'Warning'
                            when 'eror'
                              'Error'
                            when 'crit'
                              'Critical'
                            end
          record.delete('lvl')
        end
        record
      end
        
      def Parser.prefix_fields(record, prefix, regex, negate = false)
        r = {}
        record.each{|k,v|
          if (!negate && k =~ regex) || (negate && k !~ regex)
            r[prefix+k] = record[k]
          else
            r[k] = record[k]
          end
        }
        r
      end

      def Parser.parse_kv(str)
        r = {}
        if match = str.scan(/\b([A-Za-z]{1,20})=(?:([^\ "][^, ]*)|\"([^\"]+)\"),?/)
          match.each{|m|
            r[m[0]] = m[1].nil? ? m[2] : m[1]
          }
        end
        return r.empty? ? nil : r
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

      def Parser.parse_accesslog_with_referer_useragent(str)
        r,ext = Parser.parse_accesslog(str)
        if !ext.nil? && m = ext.match(/^\s+\"([^\"]+)\" \"([^\"]+)\"$/)
          r['referer'] = m[1] unless m[1] == '-'
          r['user_agent'] = m[2] unless m[2] == '-'
        end
        return r
      end

      def Parser.parse_glog(str)
        if m = str.match(/^([IWEF])(\d{4} \d\d:\d\d:\d\d\.\d{6})\s+(\S+)\s([^:]+):(\d+)\]\s+(.*)/)
          r = {}
          r['level'] = case m[1]
                       when 'I'
                         'Info'
                       when 'W'
                         'Warning'
                       when 'E'
                         'Error'
                       when 'F'
                         'Critical'
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

      # https://github.com/coreos/pkg/tree/master/capnslog
      def Parser.parse_capnslog(str)
        if m = str.match(/^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{6}) ([TDNIWEC]) \| ([^:]+):\s*(.*)/)
          r = {}
          r['timestamp'] = Time.strptime(m[1], "%Y-%m-%d %H:%M:%S.%N").iso8601(9)
          r['level'] = case m[2]
                       when 'T'
                         'Trace'
                       when 'D'
                         'Debug'
                       when 'N'
                         'Notice'
                       when 'I'
                         'Info'
                       when 'W'
                         'Warning'
                       when 'E'
                         'Error'
                       when 'C'
                         'Critical'
                       end
          r['component'] = m[3]
          r['message'] = m[4]
          return r
        else
          return nil
        end
      end

      def Parser.parse_influxdb(str)
        if m = str.match(/^\[([^\]]+)\] (.*)$/)
          r = {}
          comp = m[1]
          msg = m[2]
          if comp == 'httpd'
            ar, ext = parse_accesslog(msg)
            unless ar.nil?
              r = ar
              r['message'] = r.delete('request')
              if !ext.nil? && m = ext.match(/^ \"([^\"]+)\" \"([^\"]+)\" ([0-9a-f-]+) (\d+)$/)
                r['referer'] = m[1] unless m[1] == '-'
                r['user_agent'] = m[2]  unless m[2] == '-'
                r['request'] = m[3] unless m[3] == '-'
                r['processing_time'] = m[4] unless m[4] == '-'
              end
            end
          end
          case comp
          when 'D'
            r['level'] = 'Debug'
          when 'I'
            r['level'] = 'Info'
          when 'W'
            r['level'] = 'Warning'
          when 'E'
            r['level'] = 'Error'
          else
            r['component'] = comp
          end
          if m = msg.match(/^(\d{4}[-\/]\d\d[-\/]\d\d)[ T](\d\d:\d\d:\d\d)Z? (.*)/)
            r['timestamp'] = Time.strptime(m[1].tr('/','-')+" "+m[2]+"+00:00", "%Y-%m-%d %H:%M:%S%Z").iso8601
            r['message'] = m[3]
          elsif r['message'].nil?
            r['message'] = msg
          end
          return r
        else
          return nil
        end
      end

      def Parser.loglevel_from_dns_response(response)
        return case response
               when 'NOERROR'
                 'Info'
               when 'NODATA'
                 'Warning'
               when 'FORMERR'
                 'Warning'
               when 'SERVFAIL'
                 'Error'
               when 'NXDOMAIN'
                 'Warning'
               when 'NOTIMP'
                 'Warning'
               when 'REFUSED'
                 'Warning'
               end
      end

      def Parser.loglevel_from_http_response(response)
        return case response.to_s[0,1]
               when '2','3'
                 'Info'
               when '4'
                 'Warning'
               when '5'
                 'Error'
               end
      end

    end
  end
end
