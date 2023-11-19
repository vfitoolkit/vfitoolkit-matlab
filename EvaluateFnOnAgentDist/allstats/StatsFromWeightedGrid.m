function AllStats=StatsFromWeightedGrid(Values,Weights,npoints,nquantiles,tolerance, presorted)
% Inputs: Values is a grid of values, Weights is a grid of corresponding weights

% Output takes following form
AllStats=struct();
% AllStats.Mean=nan(1,1);
% AllStats.Median=nan(1,1);
% AllStats.Variance=nan(1,1);
% AllStats.StdDeviation=nan(1,1);
% AllStats.LorenzCurve=nan(npoints,1);
% AllStats.Gini=nan(1,1);
% AllStats.QuantileCutoffs=nan(nquantiles+1,1); % Includes the min and max values
% AllStats.QuantileMeans=nan(nquantiles,1);

if ~exist('presorted','var')
    presorted=0; % Optional input when you know that values and weights are already sorted (and zero weighted points eliminated) [and are column vectors]
end

%%
if presorted==0
    % Do I want to add unique() here???? No, you should unique before passing when appropriate (too much run time to do when unnecessary)
    Values=reshape(Values,[numel(Values),1]);
    Weights=reshape(Weights,[numel(Weights),1]);

    % Eliminate all the zero-weights from these (trivial increase in runtime, but makes it easier to spot when there is no variance)
    temp=logical(Weights~=0);
    Weights=Weights(temp);
    Values=Values(temp);

    %% Sorted weighted values
    [SortedValues,SortedValues_index] = sort(Values);

    SortedWeights = Weights(SortedValues_index);

    % WeightedValues=Values.*Weights;
    % SortedWeightedValues=WeightedValues(SortedValues_index);
elseif presorted==1
    SortedValues=Values;
    SortedWeights=Weights;
end
SortedWeightedValues=SortedValues.*SortedWeights;
CumSumSortedWeights=cumsum(SortedWeights);



%% Now the stats themselves
% Calculate the 'age conditional' mean
AllStats.Mean=sum(SortedWeightedValues);
% Calculate the 'age conditional' median
[~,index_median]=min(abs(SortedWeights-0.5));
AllStats.Median=SortedValues(index_median); % The max is just to deal with 'corner' case where there is only one element in SortedWeightedValues


%% Deal with case where all the values are just the same anyway
if SortedValues(1)==SortedValues(end)
    % The current FnsToEvaluate takes only one value, so nothing but the mean and median make sense
    AllStats.Variance=0;
    AllStats.StdDeviation=0;
    AllStats.LorenzCurve=linspace(1/npoints,1/npoints,1);
    AllStats.Gini=0;
    AllStats.QuantileCutoffs=nan(nquantiles+1,1,'gpuArray');
    AllStats.QuantileMeans=SortedValues(1)*ones(nquantiles,1);
    AllStats.Maximum=SortedValues(1);
    AllStats.Minimum=SortedValues(1);
    AllStats.MoreInequality.Top1share=0.01;
    AllStats.MoreInequality.Top5share=0.05;
    AllStats.MoreInequality.Top10share=0.1;
    AllStats.MoreInequality.Bottom50share=0.5;
    AllStats.MoreInequality.Percentile50th=SortedValues(1);
    AllStats.MoreInequality.Percentile90th=SortedValues(1);
    AllStats.MoreInequality.Percentile95th=SortedValues(1);
    AllStats.MoreInequality.Percentile99th=SortedValues(1);
else
    % Calculate the 'age conditional' variance
    AllStats.Variance=sum((Values.^2).*Weights)-(AllStats.Mean)^2; % Weighted square of values - mean^2
    if AllStats.Variance<0 && AllStats.Variance>-10^(-9) % overwrite what is likely just numerical error
        AllStats.Variance=0;
    end
    AllStats.StdDeviation=sqrt(AllStats.Variance);

    % Lorenz curve and Gini coefficient
    if npoints>0
        if SortedWeightedValues(1)<0
            AllStats.LorenzCurve=nan(npoints,1);
            AllStats.LorenzCurveComment={'Lorenz curve cannot be calculated as some values are negative'};
            AllStats.Gini=nan;
            AllStats.GiniComment={'Gini cannot be calculated as some values are negative'};
        else
            % Calculate the 'age conditional' lorenz curve
            AllStats.LorenzCurve=LorenzCurve_subfunction_PreSorted(SortedWeightedValues,CumSumSortedWeights,npoints,2);
            % Calculate the 'age conditional' gini
            AllStats.Gini=Gini_from_LorenzCurve(AllStats.LorenzCurve);
        end
    end

    % Calculate the 'age conditional' quantile means (ventiles by default)
    % Calculate the 'age conditional' quantile cutoffs (ventiles by default)
    QuantileIndexes=zeros(nquantiles-1,1,'gpuArray');
    QuantileCutoffs=zeros(nquantiles-1,1,'gpuArray');
    QuantileMeans=zeros(nquantiles,1,'gpuArray');

    for ll=1:nquantiles-1
        tempindex=find(CumSumSortedWeights>=ll/nquantiles,1,'first');

        QuantileIndexes(ll)=tempindex;
        QuantileCutoffs(ll)=SortedValues(tempindex);
        if ll==1
            QuantileMeans(ll)=sum(SortedWeightedValues(1:tempindex))./CumSumSortedWeights(tempindex); %Could equally use sum(SortedWeights(1:tempindex)) in denominator
        elseif ll<(nquantiles-1) % (1<ll) &&
            QuantileMeans(ll)=sum(SortedWeightedValues(QuantileIndexes(ll-1)+1:tempindex))./(CumSumSortedWeights(tempindex)-CumSumSortedWeights(QuantileIndexes(ll-1)));
        else %if ll==(options.nquantiles-1)
            QuantileMeans(ll)=sum(SortedWeightedValues(QuantileIndexes(ll-1)+1:tempindex))./(CumSumSortedWeights(tempindex)-CumSumSortedWeights(QuantileIndexes(ll-1)));
            QuantileMeans(ll+1)=sum(SortedWeightedValues(tempindex+1:end))./(CumSumSortedWeights(end)-CumSumSortedWeights(tempindex));
        end
    end
    % Min value
    tempindex=find(CumSumSortedWeights>=tolerance,1,'first');
    minvalue=SortedValues(tempindex);
    % Max value
    tempindex=find(CumSumSortedWeights>=(1-tolerance),1,'first');
    maxvalue=SortedValues(tempindex);
    AllStats.QuantileCutoffs=[minvalue; QuantileCutoffs; maxvalue];
    AllStats.QuantileMeans=QuantileMeans;

    % Also created min and max as dedicated entries
    AllStats.Maximum=minvalue;
    AllStats.Minimum=maxvalue;

    % Top X share indexes (npoints will be number of points in Lorenz Curve)
    Top1cutpoint=round(0.99*npoints);
    Top5cutpoint=round(0.95*npoints);
    Top10cutpoint=round(0.90*npoints);
    Top50cutpoint=round(0.50*npoints);
    AllStats.MoreInequality.Top1share=1-AllStats.LorenzCurve(Top1cutpoint);
    AllStats.MoreInequality.Top5share=1-AllStats.LorenzCurve(Top5cutpoint);
    AllStats.MoreInequality.Top10share=1-AllStats.LorenzCurve(Top10cutpoint);
    AllStats.MoreInequality.Bottom50share=AllStats.LorenzCurve(Top50cutpoint);
    % Now some cutoffs
    AllStats.MoreInequality.Percentile50th=AllStats.Median; % just a duplicate for convenience
    index_p90=find(CumSumSortedWeights>=0.90,1,'first');
    AllStats.MoreInequality.Percentile90th=SortedValues(index_p90);
    index_p95=find(CumSumSortedWeights>=0.95,1,'first');
    AllStats.MoreInequality.Percentile95th=SortedValues(index_p95);
    index_p99=find(CumSumSortedWeights>=0.99,1,'first');
    AllStats.MoreInequality.Percentile99th=SortedValues(index_p99);
end



end


