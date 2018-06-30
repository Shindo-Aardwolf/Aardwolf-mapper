# Aardwolf-mapper
blowtorch mapper for aardwolf mud client

## BlowTorch Pre-Installation instructions  
Before installing you will need to make the following changes to Blowtorch settings.
1. Bring up the menu with the menu key in the top right corner.
2. Select **Options**, then **Service**, then **GMCP Options**
3. Pleae make sure **Use GMCP** is ticked on the right hand side.
4. Press **Support String** and put "room 1", "char 1" **WITH THE quotes**. If there are any other options already there then you need a *comma* between the options. For example: "room 1", "char 1", "comm 1"

## Getting the files via zip file and putting them in the correct palce
1. To install using the zip file, you will first need to download this project from **https://github.com/Shindo-Aardwolf/Aardwolf-mapper** . In the top right hand corner is a GREEN button labled **Clone or download**. Press this button and on the right hand side of the miniwindow that pops up is **Download zip**. Press this part of the miniwindow.
2. Once the zip file has finished downloading you need to find where it downloaded to and unzip it. If you are on an Android device you may need to install an app to do this.
3. Copy **everything** from the plugins folder, of the unzipped procject, and paste it in to your **Blowtorch/plugins** folder. 

## Getting the files via raw downloads and putting them in the correct palce
This method requires slightly more interaction with github but means that you are able to update specific files later as I continue to work on the prioject.
1. A good place to start with this is to make the necessary folders in the Blowtorch**/plugins** folder. the two folders are **Shindo_DB** and **Shindo_lua**.
2. Next go to **https://github.com/Shindo-Aardwolf/Aardwolf-mapper/tree/master/plugins** and press **gmcp_mapper.xml**, this will load a page with the file displayed. On the right hand side are 3 buttons and some icons, **|raw| |blame| |history|**, press in the **|raw|** button and the page will reload, with only the text in the xml file now visible. Depending on the browser you are using you now press the download button. This will download the gmcp_mapper.xml file to your default download directory.
3. Copy **gmcp_mapper.xml** to your **Blowtorch/plugins** folder.
4. Next go to **https://github.com/Shindo-Aardwolf/Aardwolf-mapper/tree/master/plugins/Shindo_lua**. Follow the instructions in step 2 for the two lua files, **AreasArray.lua** and **gmcp_mapper.lua**.
5. Copy **AreasArray.lua** and **gmcp_mapper.lua** in to your **Blowtorch/plugins/Shindo_lua** folder
6. Next go to **https://github.com/Shindo-Aardwolf/Aardwolf-mapper/tree/master/plugins/Shindo_DB** and press **aardwolf.db**. Because this is a database file you will not see the contents of this file displayed BUT there will be 2 buttons and some icons, **|Download| |History|**. Press the **|Download|** button to download the file to your default download directory.
7. Copy **aardwolf.db** to your **Blowtorch/plugins/Shindo_DB** fodler.

## Installing in to Blowtorch
1. Start your Blowtorch session and log in to Aardwolf.
2. Press the menu button and select Plugins from the menu.
3. Press the Load button, this will bring up a list of plugins to install.
4. Scroll down to gmcp_mapper.xml and press on it. This will bring up a description of the mapper plugin and also a bulleted list of the functions that are currently available.
5. At the bottom is a button **|INSTALL PLUGIN|** press this button.
6. Please be aware that for with some android devices this will cause Blowtorch to to crash but this is not a problem. Restart Blowtorch and go back in to your aardwolf session. Before the login screen appears you should get two messages, the first "**Loading plugin file: plugins/gmcp_mapper.xml, success**" and a report from the plugin "**GMCP Mapper plugin startup**", this indicates that the plugin is correctly loaded.

### Using the plugin and the functions
The database I have provided only contains a few room from the City of Aylor. The mapper learns as you move around and explore. There are a number of quirks you need to be aware of about the way the mapper works.  
Because it is using gmcp data sent it does not map hidden exits until after you open and move through them in both directions but once this is done it will attempt to move through the hidden exit/door.  
I still have to complete porting the code for making and using custom exits. That means that you will still need to manually enter room portals and manually use custome exits.  
The functionality to use hand held portals has been coded in, I strongly suggest making and alias to use these, the mapper will use your alias, if you teach it the alias. I have and alias *vp* which is aliased to *get $1 portalbag;wear $1;enter;rem $1;put $1 portalbag;wear all* , this takes the portal named from my portalbag, which is also defined as an alias, wear the portal, enters, removes the portal, puts it back in the portal bag and then wears all. So all i have to do to define the portal to use to get to a location is to go the portal landing room and then enter *.MapperPortalAdd 5 vp garbage*.  

### Notes and Information

The quest and campaign plugin uses functions from this plugin and so if you wish to install that plugin you require this plugin as well.
