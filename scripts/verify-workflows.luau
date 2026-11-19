local fs=require('@lune/fs')
local serde=require('@lune/serde')
for _,file in {'build','publish'} do
    local workflow=serde.decode('yaml',fs.readFile('.github/workflows/'..file..'.yml'))
    assert(workflow.permissions.contents=='read','workflow permissions')
    assert(workflow.on.workflow_dispatch~=nil,'manual workflow trigger')
    for _,job in workflow.jobs do
        assert(job['runs-on']=='windows-latest','Windows build tools')
        for _,step in job.steps do
            if step.uses then assert(step.uses:match('@%x+$') and #step.uses:match('@(%x+)$')==40,'pin action commit') end
        end
    end
    if file=='publish' then
        assert(workflow.on.pull_request==nil,'pull requests cannot deploy')
        local push = workflow.on.push
        assert(#push.branches==1 and push.branches[1]=='main','release branch')
        assert(table.find(push.paths,'*.lua') and table.find(push.paths,'art/**') and table.find(push.paths,'default.project.json'),'game changes trigger publication')
        assert(workflow.jobs.publish.environment=='roblox-production','secret environment')
        assert(workflow.concurrency['cancel-in-progress']==false,'never interrupt an upload with a new deployment')
    end
end
print('Workflow YAML and release policy checks passed.')
