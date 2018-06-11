# Aardwolf-mapper
blowtorch mapper for aardwolf mud client

## BlowTorch Installation instructions  
Before installing you will need to make the following changes to Blowtorch settings.
1. Bring up the menu with the menu key in the top right corner.
2. Select **Options**, then **Service**, then **GMCP Options**
3. Pleae make sure **Use GMCP** is ticked on the right hand side.
4. Press **Support String** and put "room 1" **WITH THE quotes**. If there are any other options already there then you 
need a *comma* between the options. For example: "char 1", "room 1", "comm 1"

You need to drop everything from the src directory in to the Blowtorch plugins directory, you may need to make the Shindo_db directory in your plugind directory.

The quest and campaign plugin uses functions from this plugin and so if you wish to install that plugin you require this plugin as well.
