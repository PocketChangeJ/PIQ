#!/usr/bin/Rscript
#Rscript script commondir pwmdir tmpdir outdir bamfile pwmid
#example:
#Rscript pertf.r /cluster/thashim/basepiq/common.r /cluster/thashim/tmppiq/ /scratch/tmp/ /cluster/thashim/130130.mm10.d0/ /cluster/thashim/tmppiq/d0.RData 139

options(echo=TRUE)
args <- commandArgs(trailingOnly = TRUE)
print(args)

#location of common.r containing runtime parameters
commonfile = args[1]

#directory where pwm matches are stored
pwmdir = args[2]

#directory to use as fast temporary storage
tmpdir = args[3]

#location of output calls
outdir = args[4]

#location of the bam RData file made by bam2rdata.r
bamfile = args[5]

#which pwm file to use in pwmdir
pwmid = args[6]



#assert existence of
#commonfile
source(commonfile)
#pwmfile
load(file.path(pwmdir,paste0(pwmid,'.pwmout.RData')))
#tmpdir
load(file.path(tmpdir,paste0(pwmid,'.svout.RData')))
#outdir

#####
# make call
datadir = paste0(tmpdir,'/',pwmid,'/')

osvr=order(-sv.rotate[-(1:2)])+2
sv.rotate[osvr[1:(2*ncol(pwmin))]] = sort(sv.rotate,decreasing=T)[(2*ncol(pwmin)+1)]

validpos = list.files(datadir,paste0('positive.tf',pwmid,'-'))
chrids=match(sapply(strsplit(validpos,'[.-]'),function(i){i[3]}),ncoords)

if(sv.rotate[2] < 0){
    sv.rotate[2]=0
}

sumtr <-function(x){
    x
}

evalsvs <- function(pos.mat,neg.mat,wt){
    svps=suppressMessages(wt[(1:(2*wsize))+2]%*%pos.mat)
    svns=suppressMessages(wt[(2*wsize+1):(4*wsize)+2]%*%neg.mat)
    svps + svns + wt[1] + (sumtr(colSums(pos.mat)+colSums(neg.mat))+1) * wt[2]
}

posbgct = rep(0,2*wsize)

neglis=do.call(c,lapply(list.files(datadir,paste0('background.tf',pwmid,'-')),function(i){
    print(i)
    load(file.path(datadir,i))
    posbgct <<- posbgct + rowSums(pos.mat)
    as.double(evalsvs(pos.mat,neg.mat,sv.rotate))
}))

negcts=do.call(c,lapply(list.files(datadir,paste0('background.tf',pwmid,'-')),function(i){
    print(i)
    load(file.path(datadir,i))
    cs=colSums(pos.mat)+colSums(neg.mat)
    print(max(cs))
    cs
}))

rowsizes = rep(0,length(validpos))
posct=rep(0,2*wsize)
negct=rep(0,2*wsize)

for(i in 1:length(validpos)){
    print(i)
    load(file.path(datadir,validpos[i]))
    posct = posct + rowSums(pos.mat)
    negct = negct + rowSums(neg.mat)
    tct=colSums(pos.mat)+colSums(neg.mat)
    rowsizes[i]=ncol(pos.mat)
    pws=coords.pwm[clengths>0][[chrids[i]]]
    sv.score = as.double(evalsvs(pos.mat,neg.mat,sv.rotate))
    outputs=cbind(sv.score,tct,pws)
    writeBin(as.vector(outputs),file.path(tmpdir,paste0('tf.',pwmid,'-',ncoords[chrids[i]],'.out.bin')),8)
}

readonecol <- function(filename,rowsize,colsel){
    con=file(filename,open='rb')
    seek(con,8*rowsize*(colsel-1))
    rb=readBin(con,double(),n=rowsize,size=8)
    close(con)
    rb
}

allsvs=do.call(c,lapply(1:length(validpos),function(i){
    readonecol(file.path(tmpdir,paste0('tf.',pwmid,'-',ncoords[chrids[i]],'.out.bin')),rowsizes[i],1)
}))

allpws=do.call(c,lapply(1:length(validpos),function(i){
    readonecol(file.path(tmpdir,paste0('tf.',pwmid,'-',ncoords[chrids[i]],'.out.bin')),rowsizes[i],3)
}))

allcts=do.call(c,lapply(1:length(validpos),function(i){
    readonecol(file.path(tmpdir,paste0('tf.',pwmid,'-',ncoords[chrids[i]],'.out.bin')),rowsizes[i],2)
}))


#capf <- function(x,cap=min(c(neglis,allsvs))){y=(x-cap);y[y<=0]=1e-3;log(y+1e-3)}
#capf <- function(x,cap=(sv.rotate[1]+sv.rotate[2])){y=(x-cap);y[y<=0]=1e-3;log(y+1e-3)}
capf <- function(x,cap=(sv.rotate[1]+sv.rotate[2])){y=(x-cap-1);y[y>=0]=log(y[y>=0]+1);y};
#capf <- function(x){x}

nenrich <- function(x){
    opp=getopp(x)
    opp$objective
}

getopp <- function(x){
    rs=allpws+capf(allsvs)*x
    sorted=sort(rs,decreasing=T)
    vcut=(pwb+capf(neglis)*x)
    svcut = sort(vcut)
    maxl=min(50000,length(sorted))
    minl=min(length(sorted)/2, 100)
    ops=(findInterval(-(sorted[minl:maxl]),rev(-svcut))+10)/(minl:maxl)
    list(objective=min(ops),minimum=which.min(ops))
}

lnsrch <- function(i,sorted,svcut,regr=100){
    (length(svcut)-findInterval(sorted[i],svcut)+regr)/i
}

set.seed(1)
pwb = sample(allpws,length(neglis),replace=T)
ct.ratio = length(allpws)/length(neglis)

stepsz=0.1
alloptim=sapply(seq(stepsz,50,by=stepsz),nenrich)#
center=(which.min(alloptim))*stepsz
opt.pwm.weight=optimize(nenrich,c(max(1e-5,center-stepsz),center+stepsz))

erpen=1

scores=allpws+capf(allsvs)*opt.pwm.weight$minimum
neg.scores = pwb + capf(neglis)*opt.pwm.weight$minimum
maxl=length(scores)
enrich.ratio=erpen*(findInterval(sort(-scores)[1:maxl],sort(-neg.scores)))/(1:maxl)*ct.ratio
purity = 1/(enrich.ratio+1)
num.passed=rev(which(purity>purity.cut))[1]+50
if(is.na(num.passed)){num.passed=50}
cutv=sort(scores,decreasing=T)[num.passed]
passed.cutoff = scores > cutv

#

chrs.vec=do.call(c,lapply(1:length(validpos),function(i){
    rep(ncoords[chrids[i]],length(coords[clengths>0][[chrids[i]]]))
}))
coords.vec=do.call(c,lapply(1:length(validpos),function(i){
    start(coords[clengths>0][[chrids[i]]])
}))

df.all=data.frame(chr=chrs.vec,coord=coords.vec,pwm=allpws,shape=capf(allsvs),score=scores,purity=purity[rank(-scores)])
df.bg=df.all[passed.cutoff,]

pwname.short = gsub("[[:punct:]]","",pwmname)

write.csv(df.bg,file=file.path(outdir,paste0(pwmid,'-',pwname.short,'-calls.csv')))
write.csv(df.all,file=file.path(outdir,paste0(pwmid,'-',pwname.short,'-calls.all.csv')))

laymat = matrix(c(1,4,2,3),2,2,byrow=T)

pdf(file.path(outdir,paste0(pwmid,'-',pwname.short,'-diag.pdf')),10,7)
seqLogo(t(t(pwmin)/colSums(pwmin)))
layout(laymat)
xseq=seq(1,length(purity),length=1000)
plot(xseq,purity[xseq],type='l',xlab='Number of sites called',ylab='Purity',main='estimated PPV vs number of calls')
plot(sv.rotate[-(1:2)],type='l',sub=paste(sv.rotate[1],sv.rotate[2],sep=':'),xlab='offset from motif match, strands concatenated',ylab='score',main='Binding classifier')
abline(h=0,col='red')
plot(posct,type='l',xlab='offset from motif match',ylab='counts',main="observed counts at motif match vs background")
points(negct,col='red',type='l')
points(posbgct*ct.ratio,col='green',type='l')
legend('bottomright',col=c('black','red','green'),lwd=1,legend=c('+strand','-strand','background'))
plot(seq(stepsz,50,by=stepsz),1/(1+alloptim*ct.ratio),type='l',main='Sequence dependence vs max purity',xlab='inverse sequence dependence',ylab='max purity',log='x')
abline(v=opt.pwm.weight$minimum)
#
layout(matrix(c(1,3,4,2,2,2),2,3,byrow=T))
plot(density(scores,bw=0.1),type='l',xlab='score',ylab='density',main='Scores for \n motif match (black) vs background (red)')
points(density(neg.scores,bw=0.1),type='l',col='red')
abline(v=cutv)
spos = scores
npos = pwb+capf(neglis)*opt.pwm.weight$minimum
samp=sample(1:length(allpws),50000,replace=T)
samp.neg=sample(1:length(pwb),50000,replace=T)
plot(allpws[samp],capf(allsvs[samp]),pch=c(46,20)[passed.cutoff[samp]+1],xlab='PWM score',ylab='DNase score',main='Distribution of PWM and DNase scores in pwm match (black) vs ctrl (red)\n with called sites (bold)')
points(pwb[samp.neg],capf(neglis[samp.neg]),pch='.',col='red')
plot(allcts[samp],capf(allsvs[samp]),pch=c(46,20)[passed.cutoff[samp]+1],main='Chromatin dependence of DNase score',xlab='Summed counts',ylab='DNase score')
plot(density(log(allcts+1,10),bw=0.1),type='l',xlab='counts',ylab='density',main='Reads in 1kb for \n motif match (black) vs background (red)')
points(density(log(negcts+1,10),bw=0.1),type='l',col='red')
dev.off()

if(wsize > 200){
center = c(wsize + (-199:199))
bgpluscts = do.call(c,lapply(list.files(datadir,paste0('background.tf',pwmid,'-')),function(i){
    load(file.path(datadir,i))
    colSums(pos.mat[center,,drop=F])
}))
bgnegcts = do.call(c,lapply(list.files(datadir,paste0('background.tf',pwmid,'-')),function(i){
    load(file.path(datadir,i))
    colSums(neg.mat[center,,drop=F])
}))
pluscts = do.call(c,lapply(list.files(datadir,paste0('positive.tf',pwmid,'-')),function(i){
    load(file.path(datadir,i))
    colSums(pos.mat[center,,drop=F])
}))
negcts = do.call(c,lapply(list.files(datadir,paste0('positive.tf',pwmid,'-')),function(i){
    load(file.path(datadir,i))
    colSums(neg.mat[center,,drop=F])
}))
pwsub=order(-allpws)[1:min(10000,length(allpws))]
prank = purity[rank(-scores)][pwsub]
prank2=1/(1+exp(-log(prank)+log(1-prank)+1))
pio.plus = log((sum(pluscts[pwsub]*prank2)/sum(prank2))/(mean(bgpluscts[pwsub])))/log(2)
pio.neg = log((sum(negcts[pwsub]*prank2)/sum(prank2))/(mean(bgnegcts[pwsub])))/log(2)
pio.value = (pio.plus+pio.neg)*2
writeLines(paste0(pwmid,',',pio.value),file.path(outdir,paste0(pwmid,'-chropen.txt')))
}
