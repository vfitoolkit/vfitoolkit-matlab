function PricePathOld=TransitionPath_Case1_FHorz_shooting(PricePathOld, PricePathNames, PricePathSizeVec, ParamPath, ParamPathNames, ParamPathSizeVec, T, V_final, AgentDist_initial, n_d, n_a, n_z, N_j, d_grid,a_grid,z_gridvals_J, pi_z_J, ReturnFn, FnsToEvaluate, GeneralEqmEqns, Parameters, DiscountFactorParamNames, AgeWeights, ReturnFnParamNames, vfoptions, simoptions, transpathoptions)
% PricePathOld is matrix of size T-by-'number of prices'
% ParamPath is matrix of size T-by-'number of parameters that change over path'

% Remark to self: No real need for T as input, as this is anyway the length of PricePathOld

N_d=prod(n_d);
N_a=prod(n_a);
N_z=prod(n_z);
l_p=length(PricePathNames);


l_d=length(n_d);
if N_d==0
    l_d=0;
end
l_a=length(n_a);
l_z=length(n_z);

if transpathoptions.verbose==1
    transpathoptions
end
if transpathoptions.verbose==1
    % Set up some things to be used later
    pathnametitles=cell(1,2*length(PricePathNames));
    for ii=1:length(PricePathNames)
        pathnametitles{ii}={['Old ',PricePathNames{ii}]};
        pathnametitles{ii+length(PricePathNames)}={['New ',PricePathNames{ii}]};
    end
end

if transpathoptions.verbose==1
    DiscountFactorParamNames
    ReturnFnParamNames
    ParamPathNames
    PricePathNames
end

%% Check if using _tminus1 and/or _tplus1 variables.
if isstruct(FnsToEvaluate) && isstruct(GeneralEqmEqns)
    [tplus1priceNames,tminus1priceNames,tminus1AggVarsNames,tminus1paramNames,tplus1pricePathkk]=inputsFindtplus1tminus1(FnsToEvaluate,GeneralEqmEqns,PricePathNames,ParamPathNames);
    if transpathoptions.verbose>1
        tplus1priceNames,tminus1priceNames,tminus1AggVarsNames,tminus1paramNames,tplus1pricePathkk
    end
else
    tplus1priceNames=[];
    tminus1priceNames=[];
    tminus1paramNames=[];
    tminus1AggVarsNames=[];
    tplus1pricePathkk=[];
end
 
use_tplus1price=0;
if length(tplus1priceNames)>0
    use_tplus1price=1;
end
use_tminus1price=0;
if length(tminus1priceNames)>0
    use_tminus1price=1;
    for ii=1:length(tminus1priceNames)
        if ~isfield(transpathoptions.initialvalues,tminus1priceNames{ii})
            error('Using %s as an input (to FnsToEvaluate or GeneralEqmEqns) but it is not in transpathoptions.initialvalues \n',tminus1priceNames{ii})
        end
    end
end
use_tminus1params=0;
if length(tminus1paramNames)>0
    use_tminus1params=1;
    for ii=1:length(tminus1paramNames)
        if ~isfield(transpathoptions.initialvalues,tminus1paramNames{ii})
            error('Using %s as an input (to FnsToEvaluate or GeneralEqmEqns) but it is not in transpathoptions.initialvalues \n',tminus1paramNames{ii})
        end
    end
end
use_tminus1AggVars=0;
if length(tminus1AggVarsNames)>0
    use_tminus1AggVars=1;
    for ii=1:length(tminus1AggVarsNames)
        if ~isfield(transpathoptions.initialvalues,tminus1AggVarsNames{ii})
            error('Using %s as an input (to FnsToEvaluate or GeneralEqmEqns) but it is not in transpathoptions.initialvalues \n',tminus1AggVarsNames{ii})
        end
    end
end
% Note: I used this approach (rather than just creating _tplus1 and _tminus1 for everything) as it will be same computation.

if transpathoptions.verbose>1
    use_tplus1price
    use_tminus1price
    use_tminus1params
    use_tminus1AggVars
end

%% Change to FnsToEvaluate as cell so that it is not being recomputed all the time
AggVarNames=fieldnames(FnsToEvaluate);
for ff=1:length(AggVarNames)
    temp=getAnonymousFnInputNames(FnsToEvaluate.(AggVarNames{ff}));
    if length(temp)>(l_d+l_a+l_a+l_z)
        FnsToEvaluateParamNames(ff).Names={temp{l_d+l_a+l_a+l_z+1:end}}; % the first inputs will always be (d,aprime,a,z)
    else
        FnsToEvaluateParamNames(ff).Names={};
    end
    FnsToEvaluate2{ff}=FnsToEvaluate.(AggVarNames{ff});
end
FnsToEvaluate=FnsToEvaluate2;
% Change FnsToEvaluate out of structure form, but want to still create AggVars as a structure
simoptions.outputasstructure=1;
simoptions.AggVarNames=AggVarNames;

%% Set up GEnewprice==3 (if relevant)
if transpathoptions.GEnewprice==3
    transpathoptions.weightscheme=0;
    
    if isstruct(GeneralEqmEqns) 
        % Need to make sure that order of rows in transpathoptions.GEnewprice3.howtoupdate
        % Is same as order of fields in GeneralEqmEqns
        % I do this by just reordering rows of transpathoptions.GEnewprice3.howtoupdate
        temp=transpathoptions.GEnewprice3.howtoupdate;
        GEeqnNames=fieldnames(GeneralEqmEqns);
        for ii=1:length(GEeqnNames)
            for jj=1:size(temp,1)
                if strcmp(temp{jj,1},GEeqnNames{ii}) % Names match
                    transpathoptions.GEnewprice3.howtoupdate{ii,1}=temp{jj,1};
                    transpathoptions.GEnewprice3.howtoupdate{ii,2}=temp{jj,2};
                    transpathoptions.GEnewprice3.howtoupdate{ii,3}=temp{jj,3};
                    transpathoptions.GEnewprice3.howtoupdate{ii,4}=temp{jj,4};
                end
            end
        end
        nGeneralEqmEqns=length(GEeqnNames);
    else
        nGeneralEqmEqns=length(GeneralEqmEqns);
    end
    transpathoptions.GEnewprice3.add=[transpathoptions.GEnewprice3.howtoupdate{:,3}];
    transpathoptions.GEnewprice3.factor=[transpathoptions.GEnewprice3.howtoupdate{:,4}];
    transpathoptions.GEnewprice3.keepold=ones(size(transpathoptions.GEnewprice3.factor));
    transpathoptions.GEnewprice3.keepold=ones(size(transpathoptions.GEnewprice3.factor));
    tempweight=transpathoptions.oldpathweight;
    transpathoptions.oldpathweight=zeros(size(transpathoptions.GEnewprice3.factor));
    for ii=1:length(transpathoptions.GEnewprice3.factor)
        if transpathoptions.GEnewprice3.factor(ii)==Inf
            transpathoptions.GEnewprice3.factor(ii)=1;
            transpathoptions.GEnewprice3.keepold(ii)=0;
            transpathoptions.oldpathweight(ii)=tempweight;
        end
    end
    if size(transpathoptions.GEnewprice3.howtoupdate,1)==nGeneralEqmEqns && nGeneralEqmEqns==length(PricePathNames)
        % do nothing, this is how things should be
    else
        error('transpathoptions.GEnewprice3.howtoupdate does not fit with GeneralEqmEqns (different number of conditions/prices) \n')
    end
    transpathoptions.GEnewprice3.permute=zeros(size(transpathoptions.GEnewprice3.howtoupdate,1),1);
    for ii=1:size(transpathoptions.GEnewprice3.howtoupdate,1) % number of rows is the number of prices (and number of GE conditions)
        for jj=1:length(PricePathNames)
            if strcmp(transpathoptions.GEnewprice3.howtoupdate{ii,2},PricePathNames{jj})
                transpathoptions.GEnewprice3.permute(ii)=jj;
            end
        end
    end
    if isfield(transpathoptions,'updateaccuracycutoff')==0
        transpathoptions.updateaccuracycutoff=0; % No cut-off (only changes in the price larger in magnitude that this will be made (can be set to, e.g., 10^(-6) to help avoid changes at overly high precision))
    end
end

%%

PricePathDist=Inf;
pathcounter=1;

V_final=reshape(V_final,[N_a,N_z,N_j]);
V=zeros(size(V_final),'gpuArray'); %preallocate space
PricePathNew=zeros(size(PricePathOld),'gpuArray'); PricePathNew(T,:)=PricePathOld(T,:);
if N_d>0
    Policy=zeros(2,N_a,N_z,N_j,'gpuArray');
else
    Policy=zeros(N_a,N_z,N_j,'gpuArray');
end
AggVarsPath=zeros(T-1,length(FnsToEvaluate),'gpuArray'); % Note: does not include the final AggVars, might be good to add them later as a way to make if obvious to user it things are incorrect

AgentDist_initial=reshape(AgentDist_initial,[N_a*N_z,N_j]); % if simoptions.fastOLG==0
AgeWeights_initial=sum(AgentDist_initial,1); % [1,N_j]
if transpathoptions.ageweightstrivial==0
    % AgeWeights_T is N_j-by-T (or if simoptions.fastOLG=1, then N_a*N_j*N_z-by-T )
    AgeWeights_T=AgeWeights; % Has already been adjusted based on simoptions.fastOLG
elseif transpathoptions.ageweightstrivial==1
    if max(abs(AgeWeights_initial-AgeWeights))>10^(-13)
        error('AgeWeights differs from the weights implicit in the initial agent distribution (get different weights if calculate from AgentDist_initial vs if look in Parameters at AgeWeightsParamNames)')
    end
    AgeWeights=AgeWeights_initial;
    AgeWeightsOld=AgeWeights;
end
if simoptions.fastOLG==1
    % simoptions.fastOLG==1, so AgentDist is treated as : (a,j,z)-by-1
    AgentDist_initial=reshape(permute(reshape(AgentDist_initial,[N_a,N_z,N_j]),[1,3,2]),[N_a*N_j*N_z,1]);
    % Note: do the double reshape() as cannot get AgeWeights_initial from the final shape
    AgeWeights_initial=kron(ones(N_z,1,'gpuArray'),kron(AgeWeights_initial',ones(N_a,1,'gpuArray'))); % simoptions.fastOLG=1 so this is (a,j,z)-by-1
    % Similarly, we want pi_z_J to be (j,z,z'), but we need to keep the standard pi_z_J for the value function 
    pi_z_J_sim=gather(reshape(permute(pi_z_J(:,:,1:N_j-1),[3,1,2]),[(N_j-1)*N_z,N_z])); % For agent dist we want it to be (j,z,z')
    if transpathoptions.ageweightstrivial==0
        AgeWeights_T=kron(ones(N_z,1,'gpuArray'),kron(AgeWeights_T',ones(N_a,1,'gpuArray'))); % Vectorized as N_a*N_j*N_z-by-T
    else % AgeWeights do not change over time, so just set them all to same as AgeWeights_initial
        AgeWeights=AgeWeights_initial;
        AgeWeightsOld=AgeWeights;
    end

    % Precompute some things needed for fastOLG agent dist iteration
    exceptlastj=kron(ones(1,(N_j-1)*N_z),1:1:N_a)+kron(kron(ones(1,N_z),N_a*(0:1:N_j-2)),ones(1,N_a))+kron(N_a*N_j*(0:1:N_z-1),ones(1,N_a*(N_j-1))); % Note: there is one use of N_j which is because we want to index AgentDist
    exceptfirstj=kron(ones(1,(N_j-1)*N_z),1:1:N_a)+kron(kron(ones(1,N_z),N_a*(1:1:N_j-1)),ones(1,N_a))+kron(N_a*N_j*(0:1:N_z-1),ones(1,N_a*(N_j-1))); % Note: there is one use of N_j which is because we want to index AgentDist
    II1=repmat(1:1:(N_j-1)*N_z,1,N_z);
    II2=repmat(1:1:(N_j-1),1,N_z*N_z)+repelem((N_j-1)*(0:1:N_z-1),1,N_z*(N_j-1));
    pi_z_J_sim=sparse(II1,II2,pi_z_J_sim,(N_j-1)*N_z,(N_j-1)*N_z);
end


%%
while PricePathDist>transpathoptions.tolerance && pathcounter<transpathoptions.maxiterations
    if N_d>0
        PolicyIndexesPath=zeros(2,N_a,N_z,N_j,T-1,'gpuArray'); %Periods 1 to T-1
    else
        PolicyIndexesPath=zeros(N_a,N_z,N_j,T-1,'gpuArray'); %Periods 1 to T-1
    end
    
    %% First, go from T-1 to 1 calculating the Value function and Optimal policy function at each step. Since we won't need to keep the value
    % functions for anything later we just store the next period one in Vnext, and the current period one to be calculated in V
    V=V_final;
    for ttr=1:T-1 %so t=T-i

        for kk=1:length(PricePathNames)
            Parameters.(PricePathNames{kk})=PricePathOld(T-ttr,PricePathSizeVec(1,kk):PricePathSizeVec(2,kk));
        end
        for kk=1:length(ParamPathNames)
            Parameters.(ParamPathNames{kk})=ParamPath(T-ttr,ParamPathSizeVec(1,kk):ParamPathSizeVec(2,kk));
        end
        
        if transpathoptions.zpathtrivial==0
            pi_z_J=transpathoptions.pi_z_J_T(:,:,:,T-ttr);
            z_gridvals_J=transpathoptions.z_gridvals_J_T(:,:,:,T-ttr);
        end
        % transpathoptions.zpathtrivial==1 % Does not depend on T, so is just in vfoptions already
        
        [V, Policy]=ValueFnIter_Case1_FHorz_TPath_SingleStep(V,n_d,n_a,n_z,N_j,d_grid, a_grid, z_gridvals_J, pi_z_J, ReturnFn, Parameters, DiscountFactorParamNames, ReturnFnParamNames, vfoptions);
        % The VKron input is next period value fn, the VKron output is this period.
        % Policy is kept in the form where it is just a single-value in (d,a')
        
        if N_d>0
            PolicyIndexesPath(:,:,:,:,T-ttr)=Policy;
        else
            PolicyIndexesPath(:,:,:,T-ttr)=Policy;
        end

    end

    % Free up space on GPU by deleting things no longer needed
    clear V    
    
    %% Now we have the full PolicyIndexesPath, we go forward in time from 1 to T using the policies to update the agents distribution generating a new price path
    % Call AgentDist the current periods distn
    AgentDist=AgentDist_initial;
    if transpathoptions.ageweightstrivial==0
        AgeWeights=AgeWeights_initial;
    end
    for tt=1:T-1

        %Get the current optimal policy
        if N_d>0
            Policy=PolicyIndexesPath(:,:,:,:,tt);
        else
            Policy=PolicyIndexesPath(:,:,:,tt);
        end
        
        GEprices=PricePathOld(tt,:);

        for kk=1:length(PricePathNames)
            Parameters.(PricePathNames{kk})=PricePathOld(tt,PricePathSizeVec(1,kk):PricePathSizeVec(2,kk));
        end
        for kk=1:length(ParamPathNames)
            Parameters.(ParamPathNames{kk})=ParamPath(tt,ParamPathSizeVec(1,kk):ParamPathSizeVec(2,kk));
        end
        
        if use_tminus1price==1
            for pp=1:length(tminus1priceNames)
                if tt>1
                    Parameters.([tminus1priceNames{pp},'_tminus1'])=Parameters.(tminus1priceNames{pp});
                else
                    Parameters.([tminus1priceNames{pp},'_tminus1'])=transpathoptions.initialvalues.(tminus1priceNames{pp});
                end
            end
        end
        if use_tminus1params==1
            for pp=1:length(tminus1paramNames)
                if tt>1
                    Parameters.([tminus1paramNames{pp},'_tminus1'])=Parameters.(tminus1paramNames{pp});
                else
                    Parameters.([tminus1paramNames{pp},'_tminus1'])=transpathoptions.initialvalues.(tminus1paramNames{pp});
                end
            end
        end
        if use_tplus1price==1
            for pp=1:length(tplus1priceNames)
                kk=tplus1pricePathkk(pp);
                Parameters.([tplus1priceNames{pp},'_tplus1'])=PricePathOld(tt+1,PricePathSizeVec(1,kk):PricePathSizeVec(2,kk)); % Make is so that the time t+1 variables can be used
            end
        end
        if use_tminus1AggVars==1
            for pp=1:length(tminus1AggVarsNames)
                if tt>1
                    % The AggVars have not yet been updated, so they still contain previous period values
                    Parameters.([tminus1AggVarsNames{pp},'_tminus1'])=Parameters.(tminus1AggVarsNames{pp});
                else
                    Parameters.([tminus1AggVarsNames{pp},'_tminus1'])=transpathoptions.initialvalues.(tminus1AggVarsNames{pp});
                end
            end
        end
        
        if transpathoptions.zpathtrivial==0
            pi_z_J=transpathoptions.pi_z_J_T(:,:,:,tt);
            z_gridvals_J=transpathoptions.z_gridvals_J_T(:,:,:,tt);
            if simoptions.fastOLG==1
                pi_z_J_sim=gather(pi_z_J(1:end-1,:,:));
                pi_z_J_sim=sparse(II1,II2,pi_z_J_sim,(N_j-1)*N_z,(N_j-1)*N_z);
            end
        end
        % transpathoptions.zpathtrivial==0 % Does not depend on T, so is just in simoptions already
        
        PolicyUnKron=UnKronPolicyIndexes_Case1_FHorz(Policy, n_d, n_a, n_z, N_j,vfoptions);
        if simoptions.fastOLG==0
            AggVars=EvalFnOnAgentDist_AggVars_FHorz_Case1(AgentDist, PolicyUnKron, FnsToEvaluate, Parameters, FnsToEvaluateParamNames, n_d, n_a, n_z, N_j, d_grid, a_grid, z_gridvals_J, 2, simoptions); % The 2 is for Parallel (use GPU)
        else % simoptions.fastOLG==1
            % AgentDist has to be reshaped before passing
            AggVars=EvalFnOnAgentDist_AggVars_FHorz_Case1(permute(reshape(AgentDist,[N_a,N_j,N_z]),[1,3,2]), PolicyUnKron, FnsToEvaluate, Parameters, FnsToEvaluateParamNames, n_d, n_a, n_z, N_j, d_grid, a_grid, z_gridvals_J, 2, simoptions); % The 2 is for Parallel (use GPU)
        end
        
        %An easy way to get the new prices is just to call GeneralEqmConditions_Case1
        %and then adjust it for the current prices
            % When using negative powers matlab will often return complex
            % numbers, even if the solution is actually a real number. I
            % force converting these to real, albeit at the risk of missing problems
            % created by actual complex numbers.
        if transpathoptions.GEnewprice==1 % The GeneralEqmEqns are not really general eqm eqns, but instead have been given in the form of GEprice updating formulae
            AggVarNames=fieldnames(AggVars);
            for ii=1:length(AggVarNames)
                Parameters.(AggVarNames{ii})=AggVars.(AggVarNames{ii}).Mean;
            end
            PricePathNew(tt,:)=real(GeneralEqmConditions_Case1_v2(GeneralEqmEqns,Parameters, 2));
        elseif transpathoptions.GEnewprice==0 % THIS NEEDS CORRECTING
            % Remark: following assumes that there is one'GeneralEqmEqnParameter' per 'GeneralEqmEqn'
            for j=1:length(GeneralEqmEqns)
                AggVarNames=fieldnames(AggVars);
                for ii=1:length(AggVarNames)
                    Parameters.(AggVarNames{ii})=AggVars.(AggVarNames{ii}).Mean;
                end
                GEeqn_temp=@(GEprices) sum(real(GeneralEqmConditions_Case1_v2(GeneralEqmEqns,Parameters, 2)).^2);
                PricePathNew(tt,j)=fminsearch(GEeqn_temp,GEprices);
            end
        % Note there is no GEnewprice==2, it uses a completely different code
        elseif transpathoptions.GEnewprice==3 % Version of shooting algorithm where the new value is the current value +- fraction*(GECondn)
            AggVarNames=fieldnames(AggVars);
            for ii=1:length(AggVarNames)
                Parameters.(AggVarNames{ii})=AggVars.(AggVarNames{ii}).Mean;
            end
            p_i=real(GeneralEqmConditions_Case1_v2(GeneralEqmEqns,Parameters, 2));
            p_i=p_i(transpathoptions.GEnewprice3.permute); % Rearrange GeneralEqmEqns into the order of the relevant prices
            I_makescutoff=(abs(p_i)>transpathoptions.updateaccuracycutoff);
            p_i=I_makescutoff.*p_i;
            PricePathNew(tt,:)=(PricePathOld(tt,:).*transpathoptions.GEnewprice3.keepold)+transpathoptions.GEnewprice3.add.*transpathoptions.GEnewprice3.factor.*p_i-(1-transpathoptions.GEnewprice3.add).*transpathoptions.GEnewprice3.factor.*p_i;
        end
        
        % Sometimes, want to keep the AggVars to plot them
        if transpathoptions.graphaggvarspath==1
            for ii=1:length(AggVarNames)
                AggVarsPath(tt,ii)=AggVars.(AggVarNames{ii}).Mean;
            end
        end

        if transpathoptions.ageweightstrivial==0
            AgeWeightsOld=AgeWeights;
            AgeWeights=AgeWeights_T(:,tt);
        end

        if simoptions.fastOLG==0
            AgentDist=StationaryDist_FHorz_Case1_TPath_SingleStep_Iteration_raw(AgentDist,AgeWeights,AgeWeightsOld,Policy,N_d,N_a,N_z,N_j,pi_z_J);
        else % simoptions.fastOLG==1
            if N_d==0
                optaprime=gather(reshape(permute(Policy(:,:,1:end-1),[1,3,2]),[1,N_a*(N_j-1)*N_z])); % swap order to j,z
            else
                optaprime=gather(reshape(permute(Policy(2,:,:,1:end-1),[1,2,4,3]),[1,N_a*(N_j-1)*N_z])); % swap order to j,z
            end
            AgentDist=StationaryDist_FHorz_Case1_TPath_SingleStep_IterFast_raw(AgentDist,AgeWeights,AgeWeightsOld,optaprime,N_a,N_z,N_j,pi_z_J_sim,exceptlastj,exceptfirstj);
        end

    end
    % Free up space on GPU by deleting things no longer needed
    clear AgentDist
    
    
    % See how far apart the price paths are
    PricePathDist=max(abs(reshape(PricePathNew(1:T-1,:)-PricePathOld(1:T-1,:),[numel(PricePathOld(1:T-1,:)),1])));
    % Notice that the distance is always calculated ignoring the time t=T periods, as these needn't ever converges
    
    if transpathoptions.verbose==1     
        pathcounter
        disp('Old, New')
        % Would be nice to have a way to get the iteration count without having the whole
        % printout of path values (I think that would be useful?)
        pathnametitles{:}
        [PricePathOld,PricePathNew]
    end
    
    if transpathoptions.graphpricepath==1
        if length(PricePathNames)>12
            ncolumns=4;
        elseif length(PricePathNames)>6
            ncolumns=3;
        else
            ncolumns=2;
        end
        nrows=ceil(length(PricePathNames)/ncolumns);
        fig1=figure(1);
        for pp=1:length(PricePathNames)
            subplot(nrows,ncolumns,pp); plot(PricePathOld(:,pp))
            title(PricePathNames{pp})
        end
    end
    if transpathoptions.graphaggvarspath==1
        % Do an additional graph, this one of the AggVars
        if length(AggVarNames)>12
            ncolumns=4;
        elseif length(AggVarNames)>6
            ncolumns=3;
        else
            ncolumns=2;
        end
        nrows=ceil(length(AggVarNames)/ncolumns);
        fig2=figure(2);
        for pp=1:length(AggVarNames)
            subplot(nrows,ncolumns,pp); plot(AggVarsPath(:,pp))
            title(AggVarNames{pp})
        end
    end
    
    % Set price path to be 9/10ths the old path and 1/10th the new path (but making sure to leave prices in periods 1 & T unchanged).
    if transpathoptions.weightscheme==0
        PricePathOld=PricePathNew; % The update weights are already in GEnewprice setup
    elseif transpathoptions.weightscheme==1 % Just a constant weighting
        PricePathOld(1:T-1,:)=transpathoptions.oldpathweight.*PricePathOld(1:T-1,:)+(1-transpathoptions.oldpathweight).*PricePathNew(1:T-1,:);
    elseif transpathoptions.weightscheme==2 % A exponentially decreasing weighting on new path from (1-oldpathweight) in first period, down to 0.1*(1-oldpathweight) in T-1 period.
        % I should precalculate these weighting vectors
        Ttheta=transpathoptions.Ttheta;
        PricePathOld(1:Ttheta,:)=transpathoptions.oldpathweight*PricePathOld(1:Ttheta,:)+(1-transpathoptions.oldpathweight)*PricePathNew(1:Ttheta,:);
        PricePathOld(Ttheta:T-1,:)=((transpathoptions.oldpathweight+(1-exp(linspace(0,log(0.2),T-Ttheta)))*(1-transpathoptions.oldpathweight))'*ones(1,l_p)).*PricePathOld(Ttheta:T-1,:)+((exp(linspace(0,log(0.2),T-Ttheta)).*(1-transpathoptions.oldpathweight))'*ones(1,l_p)).*PricePathNew(Ttheta:T-1,:);
    elseif transpathoptions.weightscheme==3 % A gradually opening window.
        if (pathcounter*3)<T-1
            PricePathOld(1:(pathcounter*3),:)=transpathoptions.oldpathweight*PricePathOld(1:(pathcounter*3),:)+(1-transpathoptions.oldpathweight)*PricePathNew(1:(pathcounter*3),:);
        else
            PricePathOld(1:T-1,:)=transpathoptions.oldpathweight*PricePathOld(1:T-1,:)+(1-transpathoptions.oldpathweight)*PricePathNew(1:T-1,:);
        end
    elseif transpathoptions.weightscheme==4 % Combines weightscheme 2 & 3
        if (pathcounter*3)<T-1
            PricePathOld(1:(pathcounter*3),:)=((transpathoptions.oldpathweight+(1-exp(linspace(0,log(0.2),pathcounter*3)))*(1-transpathoptions.oldpathweight))'*ones(1,l_p)).*PricePathOld(1:(pathcounter*3),:)+((exp(linspace(0,log(0.2),pathcounter*3)).*(1-transpathoptions.oldpathweight))'*ones(1,l_p)).*PricePathNew(1:(pathcounter*3),:);
        else
            PricePathOld(1:T-1,:)=((transpathoptions.oldpathweight+(1-exp(linspace(0,log(0.2),T-1)))*(1-transpathoptions.oldpathweight))'*ones(1,l_p)).*PricePathOld(1:T-1,:)+((exp(linspace(0,log(0.2),T-1)).*(1-transpathoptions.oldpathweight))'*ones(1,l_p)).*PricePathNew(1:T-1,:);
        end
    end
    
    TransPathConvergence=PricePathDist/transpathoptions.tolerance; %So when this gets to 1 we have convergence
    if transpathoptions.verbose==1
        fprintf('Number of iterations on transition path: %i \n',pathcounter)
        fprintf('Current distance between old and new price path (in L-Infinity norm): %8.6f \n', PricePathDist)
        fprintf('Current distance to convergence: %.2f (convergence when reaches 1) \n',TransPathConvergence) %So when this gets to 1 we have convergence (uncomment when you want to see how the convergence isgoing)
    end

    if transpathoptions.historyofpricepath==1
        % Store the whole history of the price path and save it every ten iterations
        PricePathHistory{pathcounter,1}=PricePathDist;
        PricePathHistory{pathcounter,2}=PricePathOld;        
        if rem(pathcounter,10)==1
            save ./SavedOutput/TransPath_Internal.mat PricePathHistory
        end
    end

    pathcounter=pathcounter+1;
    

end


end