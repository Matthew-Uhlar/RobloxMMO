-- Original woven UI texture. No network access or uploaded image is required.
-- The five PNG masters remain in art/textures for future authorized asset import.
local Art={gui="",world={},status="World texture tiles await trusted Roblox import"}
local attempted=false
local cachedContent
local retainedImage
function Art.getGuiContent()
    if attempted then return cachedContent end
    attempted=true
    local image
    local ok,result=pcall(function()
        local size=128
        image=game:GetService("AssetService"):CreateEditableImage({Size=Vector2.new(size,size)})
        if not image then return nil end
        local pixels=buffer.create(size*size*4)
        for y=0,size-1 do
            for x=0,size-1 do
                local over=(math.floor(x/4)+math.floor(y/4))%2==0
                local weave=math.cos(2*math.pi*(if over then x else y)/4)
                local border=(x+y)%64<2 or (x-y)%64<2
                local grain=(bit32.bxor(x*193,y*97,x*y*17)%19-9)/3
                local shade=math.clamp(math.floor(199+11*weave+(if border then 16 else 0)+grain+0.5),0,255)
                local offset=(y*size+x)*4
                for channel=0,2 do buffer.writeu8(pixels,offset+channel,shade) end
                buffer.writeu8(pixels,offset+3,255)
            end
        end
        image:WritePixelsBuffer(Vector2.zero,Vector2.new(size,size),pixels)
        local content=Content.fromObject(image)
        retainedImage=image -- Keep the single shared image alive for all GUI users.
        return content
    end)
    if ok then cachedContent=result else
        if image then image:Destroy() end
    end
    return cachedContent
end
return Art
