classdef ChunkedRows < handle
    %CHUNKEDROWS Struct rows in fixed-size chunks, so a write copies one chunk.
    % MATLAB does not always update a large struct-array property in place;
    % in a fresh interactive session each write copied the whole array (about
    % 75 ms for a run-sized flip log). Chunks bound that worst case. Reads
    % assemble only the requested range.
    properties (SetAccess = private)
        Chunks
        Count = 0
        ChunkSize
        Template
    end
    methods
        function obj = ChunkedRows(template,capacity,chunkSize)
            obj.Template = template;
            obj.ChunkSize = chunkSize;
            count = max(1,ceil(max(1,capacity)/chunkSize));
            % Chunks share one blank block until first written.
            obj.Chunks = repmat({repmat(template,chunkSize,1)},count,1);
        end
        function index = append(obj,row)
            index = obj.Count+1;
            [chunk,offset] = obj.locate(index);
            if chunk > numel(obj.Chunks)
                obj.Chunks{chunk,1} = repmat(obj.Template,obj.ChunkSize,1);
            end
            obj.Chunks{chunk}(offset) = row;
            obj.Count = index;
        end
        function replace(obj,index,row)
            [chunk,offset] = obj.locate(index);
            obj.Chunks{chunk}(offset) = row;
        end
        function row = at(obj,index)
            [chunk,offset] = obj.locate(index);
            rows = obj.Chunks{chunk};
            row = rows(offset);
        end
        function values = column(obj,field,first,last)
            % One field of rows first:last as a row vector, without copying rows.
            values = repmat(obj.Template.(char(field)),1,0);
            if last < first, return; end
            for chunk = obj.locate(first):obj.locate(last)
                base = (chunk-1)*obj.ChunkSize;
                rows = obj.Chunks{chunk};
                values = [values rows(max(first-base,1):min(last-base,obj.ChunkSize)).(char(field))]; %#ok<AGROW>
            end
        end
        function rows = range(obj,first,last)
            rows = obj.Chunks{1}(1:0);
            if last < first, return; end
            parts = cell(1,0);
            for chunk = obj.locate(first):obj.locate(last)
                base = (chunk-1)*obj.ChunkSize;
                block = obj.Chunks{chunk};
                parts{end+1} = block(max(first-base,1):min(last-base,obj.ChunkSize)); %#ok<AGROW>
            end
            rows = vertcat(parts{:});
        end
    end
    methods (Access = private)
        function [chunk,offset] = locate(obj,index)
            chunk = floor((index-1)/obj.ChunkSize)+1;
            offset = index-(chunk-1)*obj.ChunkSize;
        end
    end
end
