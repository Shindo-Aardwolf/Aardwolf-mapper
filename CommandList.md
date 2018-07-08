# Mapper Commands and how to use them
In order to use thse commands you need to prefix them with a period **.**  
for example .MapperSetup  
Where functions take arguments I have include them in *italics*
## Initial Setup functions
- MapperSetup - this creates the database if you choose not to use the version supplied  
- MapperGMCPForceOn - deprecated  

## Mapper Information functions
- MapperShowThisRoom - this shows all the relevant information about the room you are in  
- MapperListAreas - this lists all the areas the mapper knows about  
- MapperListRooms  *name of room*
 This function takes part of a room name  as the argument are returns a list of all rooms that match the name. It does **NOT** create a list that you can use with any if the MapperGoto functions.
- MapperWhere *uid*  
 This function takes the uid of the target room as an argument and returns the speedwalk to the desired room. It does **NOT** take you to the room, or create a list useable with any of the MapperGoto functions.

## Mapper Cexit functions
- MapperCExitAdd *uid custom exit commands*  
- MapperCExitAddDoor *direction*  
- MapperCExitDelete  
- MapperCExitList *here/thisroom/nameofarea*  

## Mapper Portal functions
- MapperPortalAdd *level portal_command*  
- MapperPortalList  
- MapperPortalDelete *#numberfrom MapperPortalList*  

## Mapper Movement functions
- MapperGoto *uid*  
- MapperEditNote *note text*  

## Mapper recall and portal status setting
- MapperNoRecall  
- MapperNoPortal  

## Mapper report level and tier for character
- MapperReport  

## Mapper special commands for moving around rooms looked up
- MapperPopulateRoomList *name_of_room*  
- MapperPopulateRoomListArea *area/here name_of_room*  
- MapperGotoListNumber *number*
- MapperGotoListNext  
- MapperGotoListPrevious  
