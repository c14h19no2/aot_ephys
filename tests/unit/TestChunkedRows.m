classdef TestChunkedRows < matlab.unittest.TestCase
    % Bounded-write row storage shared by the timeline and trigger logs.
    methods (Test)
        function appendReplaceAndReadAcrossChunksAndGrowth(tc)
            store=ephys.ChunkedRows(TestChunkedRows.template(),3,4);
            for k=1:10, tc.verifyEqual(store.append(TestChunkedRows.row(k)),k); end
            tc.verifyEqual(store.Count,10);
            tc.verifyGreaterThanOrEqual(numel(store.Chunks),3);
            store.replace(6,TestChunkedRows.row(60));
            row=store.at(6);
            tc.verifyEqual(row.value,60);
            tc.verifyEqual(store.column("value",3,9),[3 4 5 60 7 8 9]);
            tc.verifyEqual(store.column("name",5,6),["r5" "r60"]);
            rows=store.range(2,10);
            tc.verifySize(rows,[9 1]);
            tc.verifyEqual([rows.value],[2 3 4 5 60 7 8 9 10]);
        end
        function emptyRangesKeepTheFieldTypes(tc)
            store=ephys.ChunkedRows(TestChunkedRows.template(),4,4);
            tc.verifySize(store.range(1,0),[0 1]);
            tc.verifyEqual(fieldnames(store.range(1,0)),fieldnames(TestChunkedRows.template()));
            tc.verifyClass(store.column("name",1,0),'string');
            tc.verifyClass(store.column("flag",1,0),'logical');
            tc.verifyClass(store.column("value",1,0),'double');
            tc.verifyTrue(all(store.column("name",1,0)~="x"));
        end
        function untouchedChunksStayIndependent(tc)
            % Preallocated chunks share one blank block until first written.
            store=ephys.ChunkedRows(TestChunkedRows.template(),8,4);
            store.append(TestChunkedRows.row(1));
            for k=2:6, store.append(TestChunkedRows.row(k)); end
            tc.verifyEqual(store.column("value",1,6),1:6);
            tc.verifyEqual(store.Chunks{2}(3).value,NaN);
        end
    end
    methods (Static)
        function value=template()
            value=struct('value',NaN,'name',"",'flag',false);
        end
        function value=row(k)
            value=struct('value',k,'name',"r"+k,'flag',mod(k,2)==0);
        end
    end
end
